;; -*- lexical-binding: t; -*-

(defmacro kev-fn (arglist &rest body)
  (let ((fargsym (gensym "arg")))
    `(lambda (,fargsym)
       (cl-destructuring-bind ,arglist
           ,fargsym
         ,@body))))

;; this is actually great http://clhs.lisp.se/Body/03_dd.htm
;; aslo the cl-defmacro definition has some of that info

;; requires a (require 'straight) call. so quote it for now

(defun kev-list-packages ()
  (interactive)
  (mapcar (kev-fn (build-time deps (&whole whole &key type package &allow-other-keys))
                  (print (list :pack package
                               :buildt build-time
                               :type type)))
          (hash-table-values straight--build-cache)))

;; finer grained font size control
(setq doom-font-increment 1)
(setq use-package-always-defer 't)
(setq use-package-compute-statistics 't)


;; theme shite


(setq doom-customize-theme-hook nil)
;; see https://www.ditig.com/256-colors-cheat-sheet for colors! should just do 256 tbh so
;; also, maybe can look at default doom themes for some guidance
(load-theme 'my-vibrant t)

;; is good, but it's annoying because you don't rely completely on your theme
;; but this must be set first since things rely on this I guess
(custom-set-faces!
  `(default :background ,(doom-color 'bg)))

(use-package! doom-modeline
  :init (doom-modeline-mode 1)
  :config
  ;; this sets column in modeline!
  (column-number-mode 1)

  (setq doom-modeline-height 1)
  (setq doom-modeline-percent-position nil)

  (buffer-local-value 'mode-line-format (current-buffer))

;; got rid of lsp, major-mode, misc-info
  (doom-modeline-def-modeline 'main
    '(bar window-number matches buffer-info remote-host buffer-position word-count parrot selection-info)
    '(persp-name grip irc mu4e gnus debug repl minor-modes input-method indent-info process vcs)))

(add-hook! term-mode-hook
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
  "f" (lambda ()
        (interactive)
        (print (list "use region" (use-region-p)))
        (if (use-region-p)
            (let ((m (mark))
                  (s (region-beginning)))
              (clojure-align (region-beginning) (region-end))
              (lsp-format-region (region-beginning) (region-end))
              ;; (print (list "region:" (region-beginning) (region-end)
              ;;              (region-active-p)))
              )
          (progn
            (sp-mark-sexp)
            (clojure-align (region-beginning) (region-end))
            (lsp-format-region (region-beginning) (region-end))
            (pop-mark))))
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

(add-hook! projectile-mode
  (add-to-list 'projectile-project-search-path '("~/Documents/ekata/" . 2))
  (add-to-list 'projectile-project-search-path '("~/Documents/me/" . 2)))

(setq projectile-switch-project-action #'projectile-dired)

;; makes the above thing actially work
(setq counsel-projectile-switch-project-action (lambda (project)
                                                 (dired (projectile-project-root project))))

;; delete dired buffers when switching
(define-advice dired-find-file (:around (orig-fun &rest _) dired-find-file-advice)
  (let ((prev-buf (current-buffer)))
    (funcall-interactively orig-fun)
    (when (and (eq 'dired-mode (buffer-local-value 'major-mode prev-buf))
               (not (eq prev-buf (current-buffer))))
      (kill-buffer prev-buf))))

(define-advice dired-up-directory (:around (orig-fun &rest args) dired-up-advice)
  (let ((prev-buf (current-buffer)))
    (apply #'funcall-interactively orig-fun args)
    (when (and (eq 'dired-mode (buffer-local-value 'major-mode prev-buf))
               (not (eq prev-buf (current-buffer))))
      (kill-buffer prev-buf))))


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
(setq flycheck-disabled-checkers '(emacs-lisp-checkdoc))

;; so we *can* display line numbers, but need to disable it for various
;; modes we don't want by default
(setq display-line-numbers-type t)
(remove-hook! '(prog-mode-hook text-mode-hook conf-mode-hook)
  #'display-line-numbers-mode)

;; -*- lexical-binding: t; -*-

(defmacro timed-cached-funcall (time fn)
  (let ((last-time (gensym "last-time"))
        (cached-val (gensym "cached-val"))
        (fn-args (gensym "fn-args")))
    `(let ((,last-time -100.0)
           (,cached-val nil))
       (lambda (&rest ,fn-args)
         (when (> (- (float-time) ,last-time) ,time)
           (setq ,last-time (float-time))
           (setq ,cached-val (apply (quote ,fn) ,fn-args)))
         ,cached-val))))

;; this IS necessary. fuckin shit is slow without it
;; (setq kevin-project-root "johnson")
;; (setq kevin-project-root-timer
;;       (run-with-idle-timer 1 t (lambda () (setq kevin-project-root (projectile-project-root)))))
(setq kev-cached-project-root (timed-cached-funcall 1.0 projectile-project-name))
(setq frame-title-format '((:eval
                            (funcall kev-cached-project-root))))

;; noticed bad perf here
(setq kev-cached-modeline-buffer-file-state (timed-cached-funcall 1.0 doom-modeline-update-buffer-file-state-icon))
(define-advice doom-modeline-update-buffer-file-state-icon (:around (orig-fun &rest _) doom-modeline-advice)
  (funcall kev-cached-modeline-buffer-file-state))

(use-package! browse-at-remote
  :config
  (setq browse-at-remote-remote-type-regexps
        (cons '("github.dev.pages$" . "github")
              browse-at-remote-remote-type-regexps)))

(use-package! company
  :defer 2
  :config
    (setq company-idle-delay 0.5)
    (company-mode-on))

;; idk what this for...
(global-company-mode)

(after! org
  (define-key org-mode-map (kbd "C-c f") #'org-babel-execute-src-block)

;; Including =org-tempo= restores the =<s=-style easy-templates that were
;; deprecated in Org 9.2.
  (require 'org-tempo)

  ;; start everything folded
  (setq org-startup-folded 't)
;; code blocks font
  (setq org-src-fontify-natively t)
  (setq org-src-tab-acts-natively t)
  )

(map! :mode org-mode
      :localleader
      "'"  #'org-edit-special
      "g b" #'org-mark-ring-goto)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

(use-package! org-bullets-mode
  :hook org-mode)





(setq org-roam-v2-ack t)

;; org roam to display in same window
(customize-set-variable
 'display-buffer-alist
 (append '(("\\*org-roam\\*" (display-buffer-same-window))
           ("\\*lsp-help\\*" (display-buffer-same-window)))
       display-buffer-alist))

;; define some keys everywhere
(map!
 (:prefix ("C-c n" . "Org Roam")
  "f" 'org-roam-node-find
  "d" 'org-roam-dailies-find-directory))

(use-package! org-roam
  :commands org-roam-node-find
  :custom
  (org-roam-directory "~/Documents/worknotes/org-roam")
  :bind (:map org-roam-mode-map ;; this isn't a thing now
         (("C-c n l" . org-roam)
          ("C-c n g" . org-roam-graph))
         :map org-mode-map
         (("C-c n i" . org-roam-node-insert)
          ("C-c n c" . org-id-get-create)
          ("C-c n r" . org-roam-buffer-toggle)
          ;("C-c n f" . org-roam-node-find)
          ;("C-c n d" . org-roam-dailies-find-directory)
          ))
  :config
  (setq org-roam-dailies-directory "daily/")
  ;; If you're using a vertical completion framework, you might want a more informative completion interface
  ;(setq org-roam-node-display-template (concat "${title:*} " (propertize "${tags:10}" 'face 'org-tag)))

  (org-roam-db-autosync-mode)
  )

(map! :mode emacs-lisp-mode
      :localleader
      "gg" #'elisp-slime-nav-find-elisp-thing-at-point
      "gb" #'pop-tag-mark)



(add-hook! typescript-mode
           (lsp)
           (lsp-mode 1))

(add-hook! js2-mode
           (lsp)
           (lsp-mode 1))
(map! :mode js2-mode
      :localleader
      "gg" 'js2-jump-to-definition
      "gb" #'pop-tag-mark)

(setq kevin-clojure-playbook
      '("((requiring-resolve 'vlaaad.reveal/inspect) *1)"
        "(doseq [_ (range 20)] (prn (tap> nil)))"
        "((requiring-resolve 'vlaaad.reveal/tap-log) :close-difficulty :easy)"
        "((requiring-resolve 'pjstadig.humane-test-output/activate!))"
        "((requiring-resolve 'lambdaisland.classpath/update-classpath!) {:aliases [:test :dev :local-dev]})"
        "(tap> {:vlaaad.reveal/command '(defaction ::intern-as-x [x]
                                   #(intern 'user 'x x))})"
        "(set! *warn-on-reflection* true)"))

(defun kevin-clojure-playbook (&optional output-to-current-buffer)
  "evaluate something from the playbook (w/ cider)"
  (interactive "P")

  (let ((cmd (ivy-read "clj cmd: "
                       kevin-clojure-playbook
                       :history 'kevin-clojure-playbook)))
    (cider-interactive-eval cmd
                            nil
                            (cider-defun-at-point 'bounds)
                            (cider--nrepl-pr-request-map))))


(map! :mode clojure-mode
      :localleader
      "e." (lambda (&optional output-to-current-buffer)
             (interactive "P")
             (save-excursion
               (goto-char (- (cadr (cider-list-at-point 'bounds)) 1))
               (cider-eval-last-sexp output-to-current-buffer)))
      "ef" #'cider-eval-defun-at-point
      "ep" #'kevin-clojure-playbook
      "e;" (lambda (&rest output-to-current-buffer)
             (interactive "P")
             (save-excursion
               (goto-char (- (cadr (cider-list-at-point 'bounds)) 0))
               (cider-pprint-form-to-comment 'cider-last-sexp nil)))
      "et" (lambda (&optional output-to-current-buffer)
             "run toplevel as clojure test; return report"
             (interactive "P")
             (cider-interactive-eval (concat "(binding [clojure.test/*report-counters* (ref clojure.test/*initial-report-counters*)]"
                                             "(clojure.test/test-vars [\n"
                                             (cider-defun-at-point)
                                             "])"
                                             "@clojure.test/*report-counters*)")
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

;; develop on clojure-lsp
;; ~/Documents/me/misc/clojure-lsp/
(setq lsp-clojure-custom-server-command '("~/Documents/me/misc/clojure-lsp/clojure-lsp"))

(defun lsp-clojure-nrepl-connect ()
  "Connect to the running nrepl debug server of clojure-lsp."
  (interactive)
  (let ((info (lsp-clojure-server-info-raw)))
    (save-match-data
      (when-let (port (and (string-match "\"port\":\\([0-9]+\\)" info)
                           (match-string 1 info)))
        (cider-connect-clj `(:host "localhost"
                             :port ,port))))))

(use-package! lsp-ui
  :commands lsp-ui-mode)


;; really disable cider eldoc
;; idk if this is actually needed anymore
;; (define-advice cider-eldoc-setup (:around (orig-fun) cider-eldoc-advice)
;;   nil)

(use-package! lsp-mode
  :hook ((clojure-mode . lsp)
         (clojurec-mode . lsp)
         (clojurescript-mode . lsp)
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp
  :config

  ;; add going back
  (lsp-define-conditional-key lsp-command-map
    "gb" xref-go-back "go back" t)
  ;; add paths to your local installation of project mgmt tools, like lein

  ;; disable modeline diagnostics
  ;; this takes a long time on a screen rerender. Plus I never use
  (setq lsp-modeline-diagnostics-enable nil
        ;; focus help window when it shows up
        help-window-select t
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

  ;; don't watch public dir either. alternatively move to /target bc that's the default
  (add-to-list 'lsp-file-watch-ignored-directories
               "[/\\\\]public\\'")
  ;; necessary for showing references without relative path
  (setq ivy-xref-use-file-path t)
  (setq xref-file-name-display 'project-relative)
  (setq xref-show-definitions-function #'xref-show-definitions-buffer-at-bottom)
  (after! xref
    (setq xref-show-definitions-function #'xref-show-definitions-buffer-at-bottom))

  (dolist (m '(clojure-mode
               clojurec-mode
               clojurescript-mode
               clojurex-mode))
    (add-to-list 'lsp-language-id-configuration `(,m . "clojure"))))

(add-hook! clojure-mode
  ;;(aggressive-indent-mode) this shit so slow :(
  (hs-minor-mode)

  (setq clojure-toplevel-inside-comment-form t
        ;; code alignment
        clojure-align-forms-automatically t
        )


  (defun kev-format-buffer ()
      (interactive)
      (save-excursion
        (lsp-format-buffer)
        (clojure-align (point-min) (point-max))))

  (define-clojure-indent
    (into 1)
    (do-template :form)
    (macrolet '(1 ((:defn)) nil))))

(define-advice aggressive-indent--indent-if-changed (:around (orig-fun buffer) aggressive-indent-advice)
  (when (not (with-current-buffer buffer
               (evil-insert-state-p)))
    (funcall orig-fun buffer)))

;;(setq cider-comment-prefix "\n;; => ")
(setq kev-clojure-cli-param-hist '("-M:test:dev:local-dev"
                                   "-M:cljs"
                                   "-M:local-dev:cljs:server # clj(s) projects "
                                   "-A:test:dev:local-dev -m nrepl.cmdline --middleware '[cider.nrepl/cider-middleware]' --interactive --color # no reveal for java8"
                                   ))


(use-package! cider
  ;; for some reason, this works. But after! doesn't work.
  ;; neither does `:hook (clojure-mode . cider-mode)`. Both cause the doom module
  ;; config to be ignored. This doesn't though
  :after-call clojure-mode-hook
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

;; so fucking stupid how they segregate into sesman sessions
;; This undoes that so any repl started from emacs is a candidate
;; This would break the switching repls workflow of like checking out a different
;; git branch and doing stuff, but I never do that.
;; ideally, you could just merge two sesman sessions somehow?
;; that might be better actually
(define-advice cider-repls (:around (orig-fun &optional type ensure) cider-repls-advice)
  ;;  (let ((type (cond
  ;;               ((listp type)
  ;;                (mapcar #'cider-maybe-intern type))
  ;;               ((cider-maybe-intern type))))
  ;;        (repls (seq-mapcat #'cdr
  ;;                           (sesman--linked-sessions 'CIDER 'sort))))
  ;;    (seq-filter (lambda (b)
  ;;                  (cider--match-repl-type type b))
  ;;                repls))
  (funcall orig-fun type ensure))

(define-advice nrepl-start-server-process (:around (orig-fun directory cmd on-port-callback) nrepl-start-server-process-advice)
  ;; insert prefix because sdkman doesn't insert the environment in emacs automatically
  ;; idk how to set it for the current emacs shell. may not be possible
  (let ((cmd-prefix "source \"$HOME/.sdkman/bin/sdkman-init.sh\" && { echo \"no\n\" | sdk env || echo 'no .sdkman?' } && sdk c java && "))
    (funcall orig-fun directory (concat cmd-prefix cmd) on-port-callback)))

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
