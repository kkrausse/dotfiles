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
;; This file is loaded by a small, machine-local ~/.doom.d/config.el wrapper.
;; Resolve shared files relative to this file instead of assuming anything
;; about the location of the local ~/.doom.d directory.
(defvar kev/dotfiles-doom-dir
  (file-name-directory (file-truename (or load-file-name buffer-file-name)))
  "Directory containing the shared Doom configuration.")

(add-to-list 'custom-theme-load-path
             (expand-file-name "themes" kev/dotfiles-doom-dir))
(org-babel-load-file
 (expand-file-name "orgconfig.org" kev/dotfiles-doom-dir))

;; idk wtf this does
;; (dolist (hook '(emacs-lisp-mode-hook ielm-mode-hook))
;;   (add-hook hook #'elisp-def-mode))


;; util fns
(defun my-doom-active-minor-modes ()
  (interactive)
  (mapc (lambda (mode) (print mode))
   (doom-active-minor-modes)))

(defun doom-edit-config ()
  (interactive)
  (find-file (concat doom-private-dir "orgconfig.org")))

;; idk about this
;; (bound-and-true-p company-mode)
;; (require 'smartparens-config)

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

;; Render docs lookups in-buffer via WebKit. Needs a GUI frame and an
;; xwidgets build; Doom's helper falls back to browse-url in a TTY, so
;; `emacs -nw' silently keeps the old behavior.
(setq +lookup-open-url-fn #'+lookup-xwidget-webkit-open-url-fn)
(map! "C-c w" #'xwidget-webkit-browse-url)

;; `kev/markdown-preview-xwidget' renders the current markdown buffer in a
;; WebKit view, themed from the loaded Emacs theme;
;; `kev/markdown-preview-in-browser' renders the same HTML into the default
;; browser. No keybindings yet; invoke them with M-x. Needs a markdown CLI on
;; PATH (marked, pandoc, ...).
(load-file (concat kev/dotfiles-doom-dir "local-packages/markdown-preview-xwidget.el"))

;; `ghostty-web-term' runs a real shell in a WebKit xwidget, rendered by
;; ghostty-web's WASM VT parser over a Node PTY server (one server per terminal
;; buffer). See local-packages/ghostty-web-emacs/README.md.
(load-file (concat kev/dotfiles-doom-dir "local-packages/ghostty-web-emacs/ghostty-web-term.el"))

;; Follow window selection with the keyboard, so switching to the terminal's
;; window means you can type in it.
;;
;; Emacs cannot do this by itself: nothing in the NS port hands an xwidget first
;; responder, so without help the page correctly says "Emacs has the keyboard --
;; click to type". The mode uses module/gw-focus.dylib, a small AppKit module
;; compiled on demand and loaded lazily the first time the keyboard needs to
;; move (Emacs modules cannot be unloaded, so it is not loaded at startup).
;;
;; The cost of having it on: any command that selects the terminal's window now
;; also takes the keyboard from Emacs, and `C-w' (or `C-<escape>') is the way
;; back. Prompts, macros and half-typed prefixes are excluded. Set to -1 to turn
;; it off and go back to clicking.
(ghostty-web-term-autofocus-mode 1)
