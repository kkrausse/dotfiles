  (setq frame-title-format '((:eval (projectile-project-name))))

(use-package org-bullets
  :init
  (add-hook 'org-mode-hook 'org-bullets-mode))

  ;; (setq org-ellipsis "[+]")

  (setq org-hide-emphasis-markers t)

  (setq org-src-fontify-natively t)

  (setq org-src-tab-acts-natively t)

;;(use-package zoom
;;  :hook (doom-first-input . zoom-mode)
;;  :config
;;  (setq ;;zoom-size '(0.7 . 0.7) ;; don't wanna deal with this
;;        ;; evil mode set here. basically I don't ever want to zoom in
;;        zoom-ignored-major-modes '(evil-mode dired-mode vterm-mode shell-dirtrack-mode help-mode helpful-mode rxt-help-mode help-mode-menu org-mode)
;;        zoom-ignored-buffer-names '("*doom:scratch*" "*info*" "*helpful variable: argv*" "*org-roam*")
;;        zoom-ignored-buffer-name-regexps '("^\\*calc" "\\*helpful variable: .*\\*")
;;        zoom-ignore-predicates (list (lambda () (> (count-lines (point-min) (point-max)) 20)))))

(load-theme 'my-vibrant t)
(custom-set-faces! `(default :background ,(doom-darken 'bg-alt 0.01)))

(use-package doom-modeline
  :ensure t
  :init (doom-modeline-mode 1)

  ;; this sets column in modeline!
  (column-number-mode)
  (set-face-attribute 'mode-line nil :height 90)
  (set-face-attribute 'mode-line-inactive nil :height 100)
  (setq doom-modeline-height 1)
  (face-attribute 'mode-line :height)
  (setq doom-modeline-percent-position nil)
  (buffer-local-value 'mode-line-format (current-buffer))

  (doom-modeline-def-modeline 'main
    '(bar window-number matches buffer-info remote-host buffer-position word-count parrot selection-info)
    '(misc-info persp-name grip irc mu4e gnus debug repl lsp minor-modes input-method indent-info major-mode process vcs)))

(add-hook! 'term-mode-hook
           'doom-modeline-mode)

(define-minor-mode kevin-paredit-mode
  "lisp state for paredit"
  :lighter " kevin paredit"
  (setq evil-move-beyond-eol kevin-paredit-mode))

(defmacro kevin/sp-kill-movement-fn (name &rest body)
  `(defalias (intern (concat "kevin/kill-to-"
                          (symbol-name (quote ,name))))
     (lambda ()
       (interactive)
       (let ((p (point)))
         ,@body
         (sp-kill-region p (point))))))

(evil-define-minor-mode-key
  '(normal visual) 'kevin-paredit-mode
  "B" 'sp-backward-barf-sexp
  "b" 'sp-forward-barf-sexp
  "s" 'sp-forward-slurp-sexp
  "S" 'sp-backward-slurp-sexp
  "t" 'sp-transpose-sexp
  ;; parens
  "[" 'sp-wrap-square
  "{" 'sp-wrap-curly
  "w" 'sp-wrap-round
  "W" 'sp-unwrap-sexp
  "m" 'sp-mark-sexp
  ;; killing
  "da" 'sp-splice-sexp-killing-around
  "d$" (kevin/sp-kill-movement-fn
        end-of-sexp
        (sp-end-of-sexp))
  "d0" (kevin/sp-kill-movement-fn
        beginning-of-sexp
        (sp-beginning-of-sexp))
  "dl" (kevin/sp-kill-movement-fn
        next-sexp
        (sp-forward-sexp))
  "dh" (kevin/sp-kill-movement-fn
        beginning-of-sexp
        (sp-backward-sexp))

  ;; movement
  "h" 'sp-backward-sexp
  "H" 'sp-backward-down-sexp
  "l" 'sp-forward-sexp
  "L" 'sp-down-sexp
  "j" 'sp-down-sexp
  "k" 'sp-backward-up-sexp
  "." 'kevin-paredit-mode)

(general-define-key
 :states '(normal visual)
 :keymaps 'override
 :prefix "SPC"
 "k" 'kevin-paredit-mode)

;; sets comma as spc m
(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")

;; vinegar
(define-key evil-normal-state-map (kbd "-") 'dired-jump)

;; requires key-chord package
(key-chord-define evil-insert-state-map "jj" 'evil-normal-state)
(key-chord-mode 1)
(setq key-chord-one-key-delay 0.4)

;; dont prompt on exit
(setq confirm-kill-emacs nil)
;; when exit insert mode exit
(setq evil-move-cursor-back t)

(setq display-line-numbers-type nil)
(remove-hook! '(prog-mode-hook text-mode-hook conf-mode-hook)
  #'display-line-numbers-mode)

(use-package! company
  :config
    (setq company-idle-delay 0.5)
    (company-mode-on))
(global-company-mode)

(define-key org-mode-map (kbd "C-c f") #'org-babel-execute-src-block)

(require 'org-tempo)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

(setq org-startup-folded 't)

(use-package org-roam
  :ensure t
  :hook
  ;; this builds the cache
  (after-init . org-roam-mode)
  :custom
  (org-roam-directory "~/Documents/notes/org-roam")
  :bind (:map org-roam-mode-map
         (("C-c n l" . org-roam)
          ("C-c n f" . org-roam-find-file)
          ("C-c n g" . org-roam-graph))
         :map org-mode-map
         (("C-c n i" . org-roam-insert))
         (("C-c n I" . org-roam-insert-immediate)))
  :config
  (setq org-roam-dailies-directory "daily/")

  (setq org-roam-dailies-capture-templates
        '(("d" "default" entry
           #'org-roam-capture--get-point
           "* %?"
           :file-name "daily/%<%Y-%m-%d>"
           :head "#+title: %<%Y-%m-%d>\n\n"))))

(map! :mode emacs-lisp-mode
      :localleader
      "gg" #'elisp-slime-nav-find-elisp-thing-at-point
      "gb" #'pop-tag-mark)

(map! :mode clojure-mode
      :localleader
      "e." (lambda (&optional output-to-current-buffer)
             (interactive "P")
             (save-excursion
               (goto-char (- (cadr (cider-list-at-point 'bounds)) 1))
               (cider-eval-last-sexp output-to-current-buffer)))
      "ef" #'cider-eval-defun-at-point
      "e;" (lambda (&rest output-to-current-buffer)
             (interactive "P")
             (save-excursion
               (goto-char (- (cadr (cider-list-at-point 'bounds)) 0))
               (cider-pprint-form-to-comment 'cider-last-sexp nil)))
      "en" #'cider-eval-ns-form)

(add-hook! clojure-mode
  (aggressive-indent-mode)
  ;; cider mode might be slow eval still works so gonna try disabling
  (cider-mode)

  (setq clojure-toplevel-inside-comment-form t)

  ;; code alignment

  (setq clojure-align-forms-automatically t)

  (define-clojure-indent
    (do-template 1)
    (macrolet '(1 ((:defn)) nil))))

(setq cider-inject-dependencies-at-jack-in nil)
(setq cider-jack-in-dependencies nil)
(setq cider-jack-in-auto-inject-clojure nil)
(define-advice cider-jack-in-params (:around (orig-fun project-type) jack-in-param-advice)
  "-M:test:dev:local-dev")

;;(setq cider-comment-prefix "\n;; => ")
(use-package cider
  :config
  (setq cider-comment-prefix "\n;; => "))
