(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(groovy-indent-offset 2)
 '(org-roam-db-autosync-mode t)
 '(org-src-window-setup 'current-window)
 '(safe-local-variable-values
   '((elisp-lint-indent-specs
      (describe . 1)
      (it . 1)
      (org-element-map . defun)
      (org-roam-dolist-with-progress . 2)
      (org-roam-with-temp-buffer . 1)
      (org-with-point-at . 1)
      (magit-insert-section . defun)
      (magit-section-case . 0)
      (org-roam-with-file . 2))
     (elisp-lint-ignored-validators "byte-compile" "package-lint")
     (eval font-lock-add-keywords nil
           `((,(concat "("
                       (regexp-opt
                        '("sp-do-move-op" "sp-do-move-cl" "sp-do-put-op" "sp-do-put-cl" "sp-do-del-op" "sp-do-del-cl")
                        t)
                       "\\_>")
              1 'font-lock-variable-name-face)))
     (cider-clojure-cli-global-options . "-A:test:dev")
     (cider-clojure-cli-global-options . "-M:test:dev:local-dev")
     (cider-clojure-cli-global-options . "-A:test:dev:local-dev")
     (cider-preferred-build-tool . clojure-cli)
     (cider-ns-refresh-before-fn . "repl.integrant-management/stop-repl!")
     (cider-ns-refresh-after-fn . "repl.integrant-management/start-repl!")
     (cider-known-endpoints
      ("client" "localhost" "34567"))
     (elisp-lint-indent-specs
      (if-let* . 2)
      (when-let* . 1)
      (let* . defun)
      (nrepl-dbind-response . 2)
      (cider-save-marker . 1)
      (cider-propertize-region . 1)
      (cider-map-repls . 1)
      (cider--jack-in . 1)
      (cider--make-result-overlay . 1)
      (insert-label . defun)
      (insert-align-label . defun)
      (insert-rect . defun)
      (cl-defun . 2)
      (with-parsed-tramp-file-name . 2)
      (thread-first . 1)
      (thread-last . 1))
     (checkdoc-package-keywords-flag)
     (cider-ns-refresh-before-fn . "mount.core/stop")
     (cider-ns-refresh-after-fn . "mount.core/start")
     (cider-ns-refresh-before-fn . "user/stop")
     (cider-ns-refresh-after-fn . "user/start")))
 '(use-package-compute-statistics t)
 '(xref-show-xrefs-function 'xref-show-definitions-buffer-at-bottom))
(put 'customize-variable 'disabled nil)
(put 'customize-group 'disabled nil)
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:background "grey7")))))
