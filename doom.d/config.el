;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-
;;
;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "monospace" :size 12 :weight 'semi-light)
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))
(org-babel-load-file "~/.doom.d/orgconfig.org")

;; idk wtf this does
(dolist (hook '(emacs-lisp-mode-hook ielm-mode-hook))
  (add-hook hook #'elisp-def-mode))


;; util fns
(defun my-doom-active-minor-modes ()
  (interactive)
  (mapc (lambda (mode) (print mode))
   (doom-active-minor-modes)))

(defun kevin-eval-nrepl2 ()
  (interactive)
  (eval-js-file "/Users/kkrausse/dotfiles/doom.d/kevin/nrepl2.js"))

(defun doom-edit-config ()
  (interactive)
  (find-file (concat doom-private-dir "orgconfig.org")))

(bound-and-true-p company-mode)
(js-cleanup)
(require 'smartparens-config)

;;(evil-record-macro)
;; there's also evil-execute-macro
;; a more generic macro recording / saving / replaying could be super useful


;; (eval-js-file)
;; TODO replicate:
;; (spacemacs|forall-clojure-modes m
;;     (spacemacs/set-leader-keys-for-major-mode m
;;       "e." 'cider-eval-list-at-point
;;       "lm" 'kevin-macroexpand-all
;;       "lp" 'kevin-pprint
;;       "lt" 'kevin-test
;;       "fu" 'lsp-find-references
;;       "fd" 'lsp-find-definition
;;       ))

;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.
