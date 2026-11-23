(require "../agent.scm")

(provide claude-agent)

(define (format path lines)
  (cond
    [(not lines) (string-append "@" path)]
    [(= (car lines) (cdr lines)) (string-append "@" path "#L" (number->string (car lines)))]
    [else
     (string-append "@" path "#L" (number->string (car lines)) "-" (number->string (cdr lines)))]))

(define claude-agent (agent '("claude") format))
