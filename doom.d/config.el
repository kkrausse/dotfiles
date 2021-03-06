;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "John Doe"
      user-mail-address "john@doe.com")

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

;; don't prompt on exit
(setq confirm-kill-emacs nil)

(use-package! golden-ratio
  :after-call pre-command-hook
  :config
  (golden-ratio-mode +1)
  ;; Using this hook for resizing windows is less precise than
  ;; `doom-switch-window-hook'.
  (remove-hook 'window-configuration-change-hook #'golden-ratio)
  (add-hook 'doom-switch-window-hook #'golden-ratio))

;; sets comma as spc m
(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")

;; vinegar
(define-key evil-normal-state-map (kbd "-") 'dired-jump)

;; requires key-chord (in spacemacs-additional-packages)
(setq evil-move-cursor-back t)
(key-chord-define evil-insert-state-map "jj" 'evil-normal-state)
(key-chord-mode 1)
(setq key-chord-one-key-delay 0.4)

;; load paredit
(load "~/.doom.d/kevin/kevin-paredit.el")

(load-theme 'my-vibrant t)
(custom-set-faces! `(default :background ,(doom-darken 'bg-alt 0.01)))

(eval-js "console.log('wtf')")

(dolist (hook '(emacs-lisp-mode-hook ielm-mode-hook))
  (add-hook hook #'elisp-def-mode))

(setq writeroom-fullscreen-effect t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type nil)
;; or
(remove-hook! '(prog-mode-hook text-mode-hook conf-mode-hook)
  #'display-line-numbers-mode)

;; idk they recommend company mode on the homepage
(global-company-mode)
(setq cider-inject-dependencies-at-jack-in nil)
(define-advice cider-jack-in-params (:around (orig-fun project-type) jack-in-param-advice)
  ;; this is because they got rid of cider-clojure-cli-parameters
  "-M:test:dev:local-dev")

(setq cider-jack-in-dependencies nil)
(setq cider-jack-in-auto-inject-clojure nil)
(setq clojure-toplevel-inside-comment-form t)

(map! :mode clojure-mode
      :localleader
      "e." #'cider-eval-list-at-point
      "ef" #'cider-eval-defun-at-point
      "en" #'cider-eval-ns-form)

(map! :mode (emacs-lisp-mode)
      :localleader
      "gg" #'elisp-slime-nav-find-elisp-thing-at-point
      "gb" #'xref-pop-marker-stack)

;; actually looks kind of sick to customize
;; https://github.com/seagle0128/doom-modeline
;; if I'm always running terminals in here it could be nice to get it real nice
(after! doom-modeline-mode
  (doom-modeline-init))

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

;; TODO
;; - popup for cider errors instead of other window
;; - move buffer 1,2,3,4,5,6...
;; - make symbols that cider doesn't recognise be a different color. e.g. async-clj/go-ctch
;; - clojure errors go to popwin
;; - investigate difference between clojure-layer and clojure-mode to bring back useful keybindings
;;      - might need to change clojure major mode's leader?
;; - format buffer with smartparens (bc it does that somehow)
;;      - of integrate cljfmt, or something. ask imre if there's a standard config
;; - eval sexp around point
;; - advice for dired, select file, do delete all dired buffers so back buffer works
;;
;;
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
