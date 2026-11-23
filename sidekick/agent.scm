(provide agent
         agent-cmd
         agent-format)

;; cmd: argv that starts the agent.
;; format: (path lines) -> string, lines being (start . end), 1-based, or #f for the whole file.
(struct agent (cmd format))
