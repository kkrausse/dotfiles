  (setq frame-title-format '((:eval (projectile-project-name))))

(use-package org-bullets
  :init
  (add-hook 'org-mode-hook 'org-bullets-mode))

  ;; (setq org-ellipsis "[+]")

  (setq org-hide-emphasis-markers t)

  (setq org-src-fontify-natively t)

  (setq org-src-tab-acts-natively t)

(defconst cue-keywords
  '("package" "import" "for" "in" "if" "let"))

(defconst cue-constants '("null" "true" "false"))

(defconst cue-types
  '("int" "float" "string" "bool" "bytes"))

(defvar cue--font-lock-keywords
  `(("//.*" . font-lock-comment-face)
    (,(regexp-opt cue-constants 'symbols) . font-lock-constant-face)
    (,(regexp-opt cue-keywords 'symbols) . font-lock-keyword-face)
    (,(regexp-opt cue-types 'symbols) . font-lock-type-face)))

;;;###autoload
(define-derived-mode cue-mode prog-mode "CUE"
  "Major mode for the CUE language."

  ;; Comments
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip "//[[:space:]]*")

  (setq indent-tabs-mode t)

  (setq-local font-lock-defaults '(cue--font-lock-keywords)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cue\\'" . cue-mode))

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
  :init (doom-modeline-mode 1)

  ;; this sets column in modeline!
  (column-number-mode)
  (set-face-attribute 'mode-line nil :height 90)
  (set-face-attribute 'mode-line-inactive nil :height 100)
  (setq doom-modeline-height 1)
  (face-attribute 'mode-line :height)
  (setq doom-modeline-percent-position nil)
  (buffer-local-value 'mode-line-format (current-buffer))

;; got rid of lsp, major-mode, misc-info
  (doom-modeline-def-modeline 'main
    '(bar window-number matches buffer-info remote-host buffer-position word-count parrot selection-info)
    '(persp-name grip irc mu4e gnus debug repl minor-modes input-method indent-info process vcs)))

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
 :keymaps 'global
 :prefix "SPC"
 "k" 'kevin-paredit-mode)

;; stolen from borkdude: https://github.https://github.com/borkdude/prelude/blob/master/personal/init.el#L195om/borkdude/prelude/blob/master/personal/init.el#L195
(defun copy-file-name-to-clipboard ()
  "Copy the current buffer file name to the clipboard."
  (interactive)
  (let ((filename (if (equal major-mode 'dired-mode)
                      default-directory
                    (buffer-file-name))))
    (when filename
      (kill-new filename)
      (message "Copied buffer file name '%s' to the clipboard." filename))))

;; sets comma as spc m
(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")

;; vinegar
(define-key evil-normal-state-map (kbd "-") 'dired-jump)

;; requires key-chord package
(key-chord-define evil-insert-state-map "jj" 'evil-normal-state)
(key-chord-mode 1)
(setq key-chord-one-key-delay 0.4)

;; github yank line link
;; (setq browse-at-remote-remote-type-domains
;;       (cons '("github.dev.pages" . "github") browse-at-remote-remote-type-domains))
;; dont prompt on exit
(setq confirm-kill-emacs nil)
;; when exit insert mode exit
(setq evil-move-cursor-back t)
;; c source directory so it doesn't prompt each time
(setq find-function-C-source-directory "~/Documents/me/emacs-build/emacs-ng-2/src")

;; flycheck has horrible perf.. maybe?
(setq flycheck-check-syntax-automatically '(save idle-change))

(setq kevin-project-root "johnson")
(setq kevin-project-root-timer
      (run-with-idle-timer 1 t (lambda () (setq kevin-project-root (projectile-project-root)))))
(setq frame-title-format 'kevin-project-root)

(setq display-line-numbers-type nil)
(remove-hook! '(prog-mode-hook text-mode-hook conf-mode-hook)
  #'display-line-numbers-mode)

(use-package browse-at-remote
  :config
  (setq browse-at-remote-remote-type-regexps
        (cons '("github.dev.pages$" . "github")
              browse-at-remote-remote-type-regexps)))

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

(setq org-roam-v2-ack t)
(use-package org-roam
  :hook
  ;; this builds the cache
  (after-init . org-roam-mode)
  (after-init . org-roam-db-autosync-mode)
  :custom
  (org-roam-directory "~/Documents/worknotes/org-roam")
  :bind (:map org-roam-mode-map ;; this isn't a thing now
         (("C-c n l" . org-roam)
          ("C-c n g" . org-roam-graph))
         :map org-mode-map
         (("C-c n i" . org-roam-node-insert)
          ("C-c n c" . org-id-get-create)
          ("C-c n f" . org-roam-node-find)))
  :config
  (setq org-roam-dailies-directory "daily/")
  )

(map! :mode emacs-lisp-mode
      :localleader
      "gg" #'elisp-slime-nav-find-elisp-thing-at-point
      "gb" #'pop-tag-mark)

(setq flycheck-disabled-checkers '(emacs-lisp-checkdoc))

(add-hook! js2-mode
           (lsp))
(map! :mode js2-mode
      :localleader
      "gg" 'js2-jump-to-definition
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
      "et" (lambda (&optional output-to-current-buffer)
             "run toplevel as clojure test"
             (interactive "P")
             (cider-interactive-eval (concat "(clojure.test/test-vars [\n"
                                             (cider-defun-at-point)
                                             "])")
                                     nil
                                     (cider-defun-at-point 'bounds)
                                     (cider--nrepl-pr-request-map)))
      "en" #'cider-eval-ns-form)

 (defun cider-jack-in-babashka ()
  "Start an babashka nREPL server for the current project and connect to it."
  (interactive)
  (let* ((default-directory (project-root (project-current t)))
         (process-filter (lambda (proc string)
                           "Run cider-connect once babashka nrepl server is ready."
                           (when (string-match "Started nREPL server at .+:\\([0-9]+\\)" string)
                             (cider-connect-clj (list :host "localhost"
                                                      :port (match-string 1 string)
                                                      :project-dir default-directory)))
                           ;; Default behavior: write to process buffer
                           (internal-default-process-filter proc string))))
    (set-process-filter
       (start-file-process "babashka" "*babashka*" "bb" "--nrepl-server" "0")
       process-filter)))

(use-package lsp-ui
  :commands lsp-ui-mode)

;; really disable cider eldoc
;; idk if this is actually needed anymore
;; (define-advice cider-eldoc-setup (:around (orig-fun) cider-eldoc-advice)
;;   nil)

(use-package lsp-mode
  :hook ((clojure-mode . lsp)
         (clojurec-mode . lsp)
         (clojurescript-mode . lsp)
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp
  :config
  ;; add paths to your local installation of project mgmt tools, like lein

  ;; disable modeline diagnostics
  ;; this takes a long time on a screen rerender. Plus I never use
  (setq lsp-modeline-diagnostics-enable nil
        ;; disable sideline thing
;        lsp-clojure-custom-server-command '("bash" "-c" "./clojure-lsp") ; to locally test clojure-lsp
        lsp-ui-sideline-enable nil
        company-minimum-prefix-length 1
        lsp-file-watch-threshold 10000
        lsp-diagnostics-provider :none
        gc-cons-threshold (* 100 1024 1024)
        read-prcess-output-max (* 1024 1024)
        ;; disable big obnoxious window at top
        lsp-ui-doc-enable nil
        ;; from https://www.youtube.com/watch?v=grL3DQyvneI&ab_channel=LondonClojurians
        cider-eldoc-display-for-symbol-at-point nil ;; disable cider eldoc
        cider-repl-display-help-banner nil      ;; disable help banner
        ;; no header see https://emacs-lsp.github.io/lsp-mode/tutorials/how-to-turn-off/
        lsp-headerline-breadcrumb-enable nil
        )

  ;; necessary for showing references without relative path
  (setq ivy-xref-use-file-path t)
  (setq xref-file-name-display 'project-relative)

  (dolist (m '(clojure-mode
               clojurec-mode
               clojurescript-mode
               clojurex-mode))
    (add-to-list 'lsp-language-id-configuration `(,m . "clojure"))))

(add-hook! clojure-mode
  (aggressive-indent-mode)
  (hs-minor-mode)
  ;; cider mode might be slow eval still works so gonna try disabling
  (cider-mode)

  (setq clojure-toplevel-inside-comment-form t
        ;; code alignment
        clojure-align-forms-automatically t
        )

  (define-clojure-indent
    (into 1)
    (do-template :form)
    (comment 1)
    (macrolet '(1 ((:defn)) nil))))

(define-advice aggressive-indent--indent-if-changed (:around (orig-fun buffer) aggressive-indent-advice)
  (when (not (with-current-buffer buffer
               (evil-insert-state-p)))
    (funcall orig-fun buffer)))

;;(setq cider-comment-prefix "\n;; => ")
(defvar kev-clojure-cli-param-hist '("-M:test:dev:local-dev"
                                     "-M:cljs"
                                     "-A:test:dev:local-dev -m nrepl.cmdline --middleware '[cider.nrepl/cider-middleware]' --interactive --color # no reveal for java8"
                                     )
  "cider jack in params")

(setq kev-clojure-cli-param-hist '("-M:test:dev:local-dev" "-M:cljs"
                                     "-A:test:dev:local-dev -m nrepl.cmdline --middleware '[cider.nrepl/cider-middleware]' --interactive --color # no reveal for java8"
                                     ))

(use-package cider
  :config
  (setq cider-comment-prefix "\n;; => "
        cider-repl-buffer-size-limit 100)

  ;; this is to fix the cider jack in to by my own thing because they changed some
  ;; version and got rid of =cider-clojure-cli-parameters=
  (setq cider-inject-dependencies-at-jack-in nil)
  (setq cider-jack-in-dependencies nil)
  (setq cider-jack-in-auto-inject-clojure nil)
  (define-advice cider-jack-in-params (:around (orig-fun project-type) jack-in-param-advice)
    (pcase project-type
      ('clojure-cli (ivy-read "clojure cli params: "
                              kev-clojure-cli-param-hist
                              :history 'kev-clojure-cli-param-hist))
      (_ (funcall orig-fun project-type)))))

(define-advice nrepl-start-server-process (:around (orig-fun directory cmd on-port-callback) nrepl-start-server-process-advice)
  ;; insert prefix because sdkman doesn't insert the environment in emacs automatically
  ;; idk how to set it for the current emacs shell. may not be possible
  (let ((cmd-prefix "source \"$HOME/.sdkman/bin/sdkman-init.sh\" && { echo \"no\n\" | sdk env || echo 'no .sdkman?' } && sdk c java && "))
    (funcall orig-fun directory (concat cmd-prefix cmd) on-port-callback)))
