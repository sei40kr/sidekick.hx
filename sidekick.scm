(require "helix/editor.scm")
(require "helix/misc.scm")
(require "helix/ext.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (only-in "helix/static.scm"
                  current-selection-object
                  selection->ranges
                  range->from
                  range->to
                  get-helix-cwd))
(require-builtin helix/core/text as text.)
(require-builtin steel/filesystem)
(require "sidekick/agent.scm")
(require "sidekick/mux.scm")
(require "sidekick/agent/claude.scm")
(require "sidekick/mux/herdr-app.scm")
(require "sidekick/mux/tmux.scm")

(provide sidekick-send-file
         sidekick-send-selection
         sidekick-attach
         sidekick-detach
         sidekick-register-agent!
         sidekick-set-agent!
         sidekick-register-mux!
         sidekick-set-mux!)

(define *agents* (hash "claude" claude-agent))
(define *agent* "claude")
;; (name . mux) pairs, in the order their terminals are listed.
(define *muxes* (list (cons "tmux" tmux-mux) (cons "herdr-app" herdr-app-mux)))
;; Name of the mux new agents start in, or #f to choose by where helix runs.
(define *mux* #f)
;; The terminal chosen with sidekick-attach, a hash of 'mux and 'target, or #f
;; to pick one by cwd.
(define *attached* #f)

;;@doc
;; Register an agent
;;
;; name is what sidekick-set-agent! takes. #:cmd is the argv that starts the
;; agent; muxes find its terminals by that program. #:format renders a mention
;; for its prompt from a path and lines, a (start . end) pair of 1-based line
;; numbers or #f for the whole file.
;;
;; ```scheme
;; (sidekick-register-agent! "codex"
;;   #:cmd '("codex")
;;   #:format (lambda (path lines) (string-append "@" path)))
;; ```
(define (sidekick-register-agent! name #:cmd cmd #:format format)
  (set! *agents* (hash-insert *agents* name (agent cmd format))))

;;@doc
;; Choose the agent to send to
;;
;; Takes the name it was registered with. Defaults to "claude".
(define (sidekick-set-agent! name)
  (set! *agent* name)
  (set! *attached* #f))

;;@doc
;; Register a terminal multiplexer
;;
;; name is what sidekick-set-mux! takes. Each function returns (Ok value) or
;; (Err message). #:list takes an agent's argv and returns the terminals running
;; its program, each a hash of 'target, 'cwd and 'label; an Err means the mux
;; isn't running, and its terminals are left out. #:send takes a target and
;; text and types the text into it. #:start takes an argv and a cwd and returns
;; the target of a new terminal running it.
(define (sidekick-register-mux! name #:list list-fn #:send send-fn #:start start-fn)
  (set! *muxes*
        (append (filter (lambda (p) (not (equal? (car p) name))) *muxes*)
                (list (cons name (mux list-fn send-fn start-fn))))))

;;@doc
;; Choose the terminal multiplexer agents start in
;;
;; Takes the name it was registered with. Defaults to "tmux" inside tmux and
;; "herdr-app" otherwise. Sends reach agents in every running mux either way.
(define (sidekick-set-mux! name)
  (set! *mux* name))

(define (start-mux-name)
  (or *mux* (if (inside-tmux?) "tmux" "herdr-app")))

(define (lookup-mux name)
  (define p (find-first (lambda (p) (equal? (car p) name)) *muxes*))
  (if p (cdr p) (error (string-append "unknown mux " name))))

(define (with-slash s)
  (if (ends-with? s "/") s (string-append s "/")))

;; Relative to the agent's cwd when inside it, to keep mentions short.
(define (display-path path cwd)
  (define prefix (with-slash cwd))
  (if (starts-with? path prefix)
      (substring path (string-length prefix) (string-length path))
      path))

(define (find-first pred xs)
  (cond
    [(null? xs) #f]
    [(pred (car xs)) (car xs)]
    [else (find-first pred (cdr xs))]))

(define (same-terminal? a b)
  (and (equal? (hash-ref a 'mux) (hash-ref b 'mux))
       (equal? (hash-ref a 'target) (hash-ref b 'target))))

(define (current-agent)
  (or (hash-try-get *agents* *agent*) (error (string-append "unknown agent " *agent*))))

;; The agent's terminals in every running mux, each tagged with its mux's
;; name; the start mux's come first, so they win a cwd match.
(define (terminals)
  (define argv (agent-cmd (current-agent)))
  (define first (start-mux-name))
  (define (of p)
    (define r ((mux-list (cdr p)) argv))
    (if (Ok? r)
        (map (lambda (t) (hash-insert t 'mux (car p))) (Ok->value r))
        '()))
  (apply append
         (map of
              (append (filter (lambda (p) (equal? (car p) first)) *muxes*)
                      (filter (lambda (p) (not (equal? (car p) first))) *muxes*)))))

(define (terminal-name t)
  (string-append (hash-ref t 'mux) " " (hash-ref t 'target)))

(define (fail msg)
  (set-error! (string-append "sidekick: " msg)))

(define (attach! t)
  (set! *attached* t)
  (set-status! (string-append "sidekick: attached to " (terminal-name t))))

(define (start!)
  (define name (start-mux-name))
  (define r ((mux-start (lookup-mux name)) (agent-cmd (current-agent)) (get-helix-cwd)))
  (if (Ok? r)
      (attach! (hash 'mux name 'target (Ok->value r)))
      (fail (Err->value r))))

;; Returns (Ok terminal) or (Err message).
(define (resolve-terminal)
  (define ts (terminals))
  (define cwd (get-helix-cwd))
  (cond
    [*attached*
     (define t (find-first (lambda (t) (same-terminal? t *attached*)) ts))
     (if t
         (Ok t)
         (let ([gone *attached*])
           (set! *attached* #f)
           (Err (string-append (terminal-name gone) " is gone, detached"))))]
    [else
     (define t (find-first (lambda (t) (equal? (hash-ref t 'cwd) cwd)) ts))
     (if t
         (Ok t)
         (Err (string-append "no " *agent* " terminal in " cwd ", run :sidekick-attach")))]))

(define (send! mentions)
  (define a (current-agent))
  (define r (resolve-terminal))
  (if (Err? r)
      (fail (Err->value r))
      (let* ([t (Ok->value r)]
             [m (lookup-mux (hash-ref t 'mux))]
             [target (hash-ref t 'target)]
             [text (string-append (string-join (map (lambda (m)
                                                      ((agent-format a)
                                                       (display-path (car m) (hash-ref t 'cwd))
                                                       (cdr m)))
                                                   mentions)
                                              " ")
                                 " ")])
        ;; Off the main thread, since a mux may block until the terminal accepts input.
        (spawn-native-thread
         (lambda ()
           (define r ((mux-send m) target text))
           (hx.with-context (lambda ()
                              (if (Err? r)
                                  (fail (Err->value r))
                                  (set-status! (string-append "sidekick: sent to " (terminal-name t))))))))
        (set-status! (string-append "sidekick: sending to " (terminal-name t))))))

(define (current-path)
  (editor-document->path (editor->doc-id (editor-focus))))

;;@doc
;; Send file to agent
;;
;; Mentions the current file in the agent's prompt.
(define (sidekick-send-file)
  (define path (current-path))
  (if path
      (send! (list (cons path #f)))
      (fail "buffer has no file")))

;;@doc
;; Send selected lines to agent
;;
;; Mentions the lines of each selection in the agent's prompt.
(define (sidekick-send-selection)
  (define path (current-path))
  (define rope (editor->text (editor->doc-id (editor-focus))))
  (define (line-of pos)
    (+ (text.rope-char->line rope pos) 1))
  (if path
      (send! (map (lambda (r)
                    ;; to is exclusive: a whole-line selection ends at the next line's start.
                    (cons path
                          (cons (line-of (range->from r))
                                (line-of (max (range->from r) (- (range->to r) 1))))))
                  (selection->ranges (current-selection-object))))
      (fail "buffer has no file")))

;; --- picker

;; The only picker Steel can open lists files and opens the chosen one, so each
;; entry is a file named after its terminal, closed again once chosen.
(define *new-entry* "+ new")

(define (picker-dir)
  (string-append (with-handler (lambda (e) "/tmp") (env-var "XDG_RUNTIME_DIR")) "/sidekick-hx"))

(define (write-entry! dir name contents)
  (define port (open-output-file (string-append dir "/" name) #:exists 'truncate))
  (write-string contents port)
  (close-output-port port))

(define (entry-name t)
  ;; Labels such as herdr-app's "space / tab" can hold slashes, which file names can't.
  (string-append (terminal-name t) "  " (string-replace (hash-ref t 'label) "/" "|")))

(define (on-pick dir)
  (define path (editor-document->path (editor->doc-id (editor-focus))))
  (when (and path (starts-with? path (with-slash dir)))
    (define name (file-name path))
    (helix.buffer-close)
    (if (equal? name *new-entry*)
        (start!)
        (let ([words (split-whitespace name)])
          (attach! (hash 'mux (car words) 'target (cadr words)))))))

(define (pick terminals)
  (define dir (picker-dir))
  (when (path-exists? dir)
    (for-each delete-file! (read-dir dir)))
  (unless (path-exists? dir)
    (create-directory! dir))
  (for-each (lambda (t)
              (write-entry! dir (entry-name t) (string-append (hash-ref t 'label) "\n" (hash-ref t 'cwd) "\n")))
            terminals)
  (write-entry! dir *new-entry* (string-append "Start " *agent* " in " (get-helix-cwd) "\n"))
  (push-component! (#%exp-picker (read-dir dir) (lambda () (on-pick dir)))))

;;@doc
;; Attach to an agent terminal
;;
;; Sends go to that terminal until :sidekick-detach. With a target, attaches to
;; it. Without one, picks from the agent's terminals, or starts the agent when
;; none is running.
(define (sidekick-attach [target #f])
  (define ts (terminals))
  (cond
    [target
     (define t (find-first (lambda (t) (equal? (hash-ref t 'target) target)) ts))
     (if t
         (attach! t)
         (fail (string-append target " is not running " *agent*)))]
    [(null? ts) (start!)]
    [else (pick ts)]))

;;@doc
;; Detach from the agent terminal
;;
;; Sends go to the agent's terminal in helix's cwd again.
(define (sidekick-detach)
  (set! *attached* #f)
  (set-status! "sidekick: detached"))
