(require-builtin steel/filesystem)
(require "../mux.scm")
(require "../run.scm")

(provide herdr-app-mux)

;; hc wraps text sent from inside a herdr-core terminal in an <hc from="..."> tag,
;; and Claude Code doesn't treat an @-mention inside the tag as one.
(define (hc args)
  (run "hc" args #:env '(("HC_TERMINAL_ID" . ""))))

(define (json r)
  (string->jsexpr (Ok->value r)))

;; hc ls leaves out what runs in the foreground, such as an agent started from
;; a shell, so each terminal needs its own hc get.
(define (foreground t)
  (define r (hc (list "get" (hash-ref t 'address) "--json")))
  ;; A terminal can end between hc ls and hc get.
  (and (Ok? r) (hash-try-get (json r) 'foreground)))

(define (terminal t program)
  (define fg (foreground t))
  (and fg
       (equal? (file-name (car (hash-ref fg 'argv))) program)
       (hash 'target (hash-ref t 'address)
             'cwd (hash-ref fg 'cwd)
             ;; Terminals without a pane have no place in the window.
             'label (or (hash-try-get t 'where) (hash-ref t 'address)))))

(define (list-terminals argv)
  (define r (hc (list "ls" "--json")))
  (define program (file-name (car argv)))
  (if (Err? r)
      r
      (Ok (filter (lambda (t) t)
                  (map (lambda (t) (terminal t program)) (hash-ref (json r) 'terminals))))))

;; hc send also presses Enter (herdrdev/herdr-core#215); sidekick assumes it only types.
(define (send target text)
  (hc (list "send" target text)))

;; Opens beside the focused pane, which is the one running helix.
(define (start argv cwd)
  (define r
    (run "herdr-app"
         (list "do" "terminal.open"
               "--argv" (value->jsexpr-string argv)
               "--folder" cwd
               "--place" "right")))
  (if (Err? r)
      r
      (Ok (hash-ref (json r) 'terminal))))

(define herdr-app-mux (mux list-terminals send start))
