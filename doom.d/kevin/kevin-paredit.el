;; should be called in load

(evil-define-state kevin-paredit
  "Lisp state.
 Used to navigate lisp code and manipulate the sexp tree."
  :tag " <L> "
  :suppress-keymap t
  :cursor (box . 2)
  (if (evil-kevin-paredit-state-p) (smartparens-mode)))

(defun kevin-paredit-state-toggle ()
  "Toggle the lisp state."
  (interactive)
  (if (eq 'kevin-paredit evil-state)
      (progn
        (message "state: lisp -> normal")
        (evil-normal-state))
    (message "state: %s -> lisp" evil-state)
    (evil-kevin-paredit-state)))

(defvar kevin-paredit-bindings '(("B" 'sp-backward-barf-sexp)
                                 ("b" 'sp-forward-barf-sexp)
                                 ("s" 'sp-forward-slurp-sexp)
                                 ("S" 'sp-backward-slurp-sexp)
                                 ("t" 'sp-transpose-sexp)
                                 ("[" 'sp-wrap-square)
                                 ("{" 'sp-wrap-curly)
                                 ("w" 'sp-wrap-round)
                                 ("W" 'sp-unwrap-sexp)
                                 ;; movement
                                 ("h" 'sp-backward-sexp)
                                 ("H" 'sp-backward-down-sexp)
                                 ("l" 'sp-forward-sexp)
                                 ("L" 'sp-down-sexp)
                                 ("k" 'sp-backward-up-sexp)
                                 ("i" (lambda ()
                                        (interactive)
                                        (kevin-paredit-state-toggle)
                                        (evil-insert-state)))
                                 ("." 'kevin-paredit-state-toggle)))

(dolist (binding kevin-paredit-bindings)
  (define-key evil-kevin-paredit-state-map (kbd (car binding)) (eval (cadr binding) t)))

(map! :mode evil-normal-state-map
      :leader
      "k" #'kevin-paredit-state-toggle)
