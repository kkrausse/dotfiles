(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(safe-local-variable-values
   '((cider-clojure-cli-global-options . "-A:test:dev:http-drivers:local-dev")
     (eval define-clojure-indent
           (codepoint-case 'defun))
     (cider-clojure-cli-global-options . "-M:test:local-dev")
     (cider-clojure-cli-global-options . "-M:test:dev:local-dev")
     (cider-known-endpoints
      ("client" "localhost" "34567"))
     (cider-ns-refresh-before-fn . "user/stop")
     (cider-ns-refresh-after-fn . "user/start")
     (cider-clojure-cli-global-options . "-A:test:dev:local-dev")
     (cider-preferred-build-tool . clojure-cli)
     (eval font-lock-add-keywords nil
           `((,(concat "("
                       (regexp-opt
                        '("sp-do-move-op" "sp-do-move-cl" "sp-do-put-op" "sp-do-put-cl" "sp-do-del-op" "sp-do-del-cl")
                        t)
                       "\\_>")
              1 'font-lock-variable-name-face)))
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
     (checkdoc-package-keywords-flag))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:background "#221414"))))
 '(bg ((((class color) (min-colors 257)) (:foreground "#568751")) (((class color) (min-colors 256)) (:foreground "#6b8247")) (((class color) (min-colors 16)) (:foreground "#6b8247"))))
 '(doom-modeline-buffer-project-root ((((class color) (min-colors 257)) (:foreground "#7bc275" :weight bold)) (((class color) (min-colors 256)) (:foreground "#99bb66" :weight bold)) (((class color) (min-colors 16)) (:foreground "#99bb66" :weight bold)))))
