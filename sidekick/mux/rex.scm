(require-builtin steel/filesystem)
(require "../mux.scm")
(require "../run.scm")

(provide rex-mux
         inside-rex?)

;; Without --autostart=false, listing would start a rex server that isn't running.
(define (rex args)
  (run "rex" (cons "--autostart=false" args)))

(define (json r)
  (string->jsexpr (Ok->value r)))

(define (call block method args)
  (rex (list "block" "call" "-b" block method (value->jsexpr-string args))))

;; argv0 rather than name, which is the resolved executable, such as
;; coreutils for cat or .claude-wrapped for claude.
(define (program p)
  (file-name (or (hash-try-get p 'argv0) (hash-ref p 'name))))

(define (terminal session block prog)
  (define r (call (hash-ref block 'block_id) "process" (hash)))
  ;; Blocks that aren't terminals have no process method, and a block can close
  ;; between rex block ls and rex block call.
  (define fg (and (Ok? r) (hash-try-get (json r) 'foreground)))
  (and fg
       (equal? (program fg) prog)
       (hash 'target (hash-ref block 'block_id)
             'cwd (hash-ref fg 'cwd)
             'label (string-append (hash-ref session 'label) ":" (hash-ref block 'label)))))

(define (session-terminals session prog)
  (define r (rex (list "block" "ls" "-s" (hash-ref session 'session_id) "--json")))
  (if (Err? r)
      '()
      (filter (lambda (t) t)
              (map (lambda (b) (terminal session b prog)) (hash-ref (json r) 'blocks)))))

(define (list-terminals argv)
  (define r (rex (list "ls" "--json")))
  (define prog (file-name (car argv)))
  (if (Err? r)
      r
      (Ok (apply append
                 (map (lambda (s) (session-terminals s prog)) (hash-ref (json r) 'sessions))))))

(define (bracketed-paste? target)
  (define r (call target "modes" (hash)))
  (and (Ok? r)
       (not (null? (filter (lambda (m) (and (equal? (hash-ref m 'name) "bracketed_paste") (hash-ref m 'set)))
                           (hash-ref (json r) 'modes))))))

(define esc (string (integer->char 27)))

;; A bracketed paste when the agent accepts one, so it takes the text as typed
;; input rather than keys to act on one by one, such as @ opening a file completion.
(define (send target text)
  (call target
        "write"
        (hash 'data
              (if (bracketed-paste? target)
                  (string-append esc "[200~" text esc "[201~")
                  text))))

;; Splits the block running helix, or rex's focused block when that's unknown.
(define (start argv cwd)
  (define block (with-handler (lambda (e) #f) (env-var "REX_BLOCK")))
  (define r
    (rex (append (list "split" "--json" "-c" cwd)
                 (if block (list "-b" block) '())
                 (cons "--" argv))))
  (if (Err? r)
      r
      (Ok (car (hash-ref (json r) 'block_ids)))))

(define rex-mux (mux list-terminals send start))

;; REX_BLOCK alone can't tell: a process can inherit it from a block that's gone.
(define (inside-rex?)
  (define block (with-handler (lambda (e) #f) (env-var "REX_BLOCK")))
  (and block (Ok? (rex (list "block" "inspect" block)))))
