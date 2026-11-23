(provide mux
         mux-list
         mux-send
         mux-start)

;; Every function returns (Ok value) or (Err message).
;; list: (argv) -> terminals whose foreground program is argv's, each a hash of 'target, 'cwd and 'label.
;;   An Err means the mux isn't running.
;; send: (target text) -> anything; types text into the terminal.
;; start: (argv cwd) -> target of a new terminal running argv in cwd.
(struct mux (list send start))
