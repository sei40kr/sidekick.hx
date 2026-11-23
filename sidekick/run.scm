(provide run)

;; Runs prog and returns (Ok stdout), or (Err message) when it can't start or fails.
;; env is a list of (name . value) pairs to set for prog.
(define (run prog args #:env [env '()])
  (define result
    (~> (foldl (lambda (pair cmd) (with-env-var cmd (car pair) (cdr pair))) (command prog args) env)
        with-stdout-piped
        ;; Inheriting stderr would draw over the editor.
        (with-stderr (open-output-file "/dev/null" #:exists 'update))
        spawn-process))
  (if (Err? result)
      (Err (string-append "failed to run " prog))
      (let* ([child (Ok->value result)]
             [out (read-port-to-string (child-stdout child))]
             [code (Ok->value (wait child))])
        (if (= code 0)
            (Ok out)
            (Err (string-append prog " " (car args) " exited with " (number->string code)))))))
