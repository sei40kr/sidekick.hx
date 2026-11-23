(require-builtin steel/filesystem)
(require "../mux.scm")
(require "../run.scm")

(provide tmux-mux
         inside-tmux?)

(define (lines s)
  (filter (lambda (l) (not (equal? l ""))) (split-many s "\n")))

;; pid -> (tpgid . program) for every process, from one ps call.
(define (processes)
  (define r (run "ps" (list "-eo" "pid=,tpgid=,args=")))
  (if (Err? r)
      r
      (Ok (foldl (lambda (line table)
                   (define words (split-whitespace line))
                   (if (< (length words) 3)
                       table
                       (hash-insert table (car words) (cons (cadr words) (file-name (caddr words))))))
                 (hash)
                 (lines (Ok->value r))))))

;; tmux knows a pane's shell, not what runs in it, so follow the shell's
;; terminal to its foreground process group, whose leader is the program.
(define (foreground-program procs pane-pid)
  (define shell (hash-try-get procs pane-pid))
  (define leader (and shell (hash-try-get procs (car shell))))
  (cond
    [leader (cdr leader)]
    [shell (cdr shell)]
    [else #f]))

(define (list-terminals argv)
  (define program (file-name (car argv)))
  (define panes
    (run "tmux"
         (list "list-panes" "-a" "-F"
               "#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{session_name}:#{window_index}.#{pane_index}")))
  (define procs (processes))
  (cond
    [(Err? panes) panes]
    [(Err? procs) procs]
    [else
     (Ok (filter (lambda (t) t)
                 (map (lambda (line)
                        (define fields (split-many line "\t"))
                        (and (equal? (foreground-program (Ok->value procs) (list-ref fields 1)) program)
                             (hash 'target (list-ref fields 0)
                                   'cwd (list-ref fields 2)
                                   'label (list-ref fields 3))))
                      (lines (Ok->value panes)))))]))

;; A bracketed paste, so the agent takes the text as typed input rather than
;; keys to act on one by one, such as @ opening a file completion.
(define (send target text)
  (run "tmux"
       (list "set-buffer" "-b" "sidekick" "--" text
             ";" "paste-buffer" "-p" "-d" "-b" "sidekick" "-t" target)))

;; Splits the pane running helix, or tmux's current pane when that's unknown.
(define (start argv cwd)
  (define pane (with-handler (lambda (e) #f) (env-var "TMUX_PANE")))
  (define r
    (run "tmux"
         (append (list "split-window" "-h" "-P" "-F" "#{pane_id}" "-c" cwd)
                 (if pane (list "-t" pane) '())
                 (cons "--" argv))))
  (if (Err? r)
      r
      (Ok (trim (Ok->value r)))))

(define tmux-mux (mux list-terminals send start))

;; TMUX alone can't tell: a process can inherit it from a tmux that's gone.
(define (inside-tmux?)
  (and (with-handler (lambda (e) #f) (env-var "TMUX"))
       (Ok? (run "tmux" (list "display-message" "-p" "")))))
