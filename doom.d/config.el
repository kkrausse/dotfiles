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

(load-theme 'my-vibrant t)

(evil-define-state kevin-paredit
  "Lisp state.
 Used to navigate lisp code and manipulate the sexp tree."
  :tag " <L> "
  :suppress-keymap t
  :cursor (bar . 2)
  (if (evil-lisp-state-p) (smartparens-mode)))

(defun kevin-paredit-state-toggle ()
  "Toggle the lisp state."
  (interactive)
  (if (eq 'kevin-paredit evil-state)
      (progn
        (message "state: lisp -> normal")
        (evil-normal-state))
    (message "state: %s -> lisp" evil-state)
    (evil-kevin-paredit-state)))

(mapc (lambda (binding)
        (define-key evil-kevin-paredit-state-map (kbd (car binding)) (eval (cadr binding) t)))
      '(("B" 'sp-backward-barf-sexp)
        ("b" 'sp-forward-barf-sexp)
        ("s" 'sp-forward-slurp-sexp)
        ("S" 'sp-backward-slurp-sexp)
        ("t" 'sp-transpose-sexp)
        ("w" 'sp-wrap)
        ("[" 'sp-wrap-square)
        ("{" 'sp-wrap-curly)
        ;; movement
        ("h" 'sp-backward-sexp)
        ("l" 'sp-forward-sexp)
        ("k" 'sp-backward-up-sexp)
        ("j" 'sp-down-sexp)
        ("i" (lambda () (interactive) (kevin-paredit-state-toggle) (evil-insert)))
        ("." 'kevin-paredit-state-toggle)))

(define-minor-mode kevin-paredit-mode
  "paredit mode"
  :init-value t
  :lighter " kevin paredit"
  :keymap (let ((map (make-sparse-keymap)))
            (mapc (lambda (binding)
                    (define-key map (kbd (car binding)) (eval (cadr binding) t)))
                  '(("B" 'sp-backward-barf-sexp)
                    ("b" 'sp-forward-barf-sexp)
                    ("s" 'sp-forward-slurp-sexp)
                    ("S" 'sp-backward-slurp-sexp)
                    ("t" 'sp-transpose-sexp)
                    ("w" 'sp-wrap)
                    ("[" 'sp-wrap-square)
                    ("{" 'sp-wrap-curly)
                    ;; movement
                    ("h" 'sp-backward-sexp)
                    ("l" 'sp-forward-sexp)
                    ("k" 'sp-backward-up-sexp)
                    ("j" 'sp-down-sexp)
                    ("i" (lambda () (interactive) (kevin-paredit-mode) (evil-insert)))
                    ("." 'kevin-paredit-mode)))
            map)
  :after-hook (if kevin-paredit-mode
                  (progn
                    (print "fudging alist")
                    (setq evil-move-beyond-eol t)
                    (setq minor-mode-map-alist (assq-delete-all 'kevin-paredit-mode minor-mode-map-alist))
                    (add-to-list 'minor-mode-map-alist '(kevin-paredit-mode kevin-paredit-mode-map)))
                  (setq evil-move-beyond-eol nil)))

;;(defadvice load (:after))
(print (mapcar (lambda (x) (car x)) minor-mode-map-alist))
;; (define-globalized-minor-mode kevin-paredit-global-mode kevin-paredit-mode
;;   (lambda ()
;;     (if (not (minibufferp (current-buffer)))
;;         (kevin-paredit-mode -1))))
;;(define-globalized-minor-mode global-kevin-paredit-mode kevin-paredit-mode kevin-paredit-mode)
(define-advice load (:around (orig-fun &rest args) paredit-overried)
  (setq minor-mode-map-alist (assq-delete-all 'kevin-paredit-mode minor-mode-map-alist))
  (add-to-list 'minor-mode-map-alist '(kevin-paredit-mode kevin-paredit-mode-map))
  (apply orig-fun args))

(add-to-list 'emulation-mode-map-alists '(kevin-paredit-mode kevin-paredit-mode-map))

(map! :mode evil-normal-state-map
      :leader
      "k"
      #'kevin-paredit-mode)

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


;; TODO
;; - mini paredit mode
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
