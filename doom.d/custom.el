(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(safe-local-variable-values
   '((cider-ns-refresh-before-fn . "user/stop")
     (cider-ns-refresh-after-fn . "user/start")
     (cider-clojure-cli-global-options . "-A:test:dev")
     (cider-preferred-build-tool . clojure-cli))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:background "#221414")))))
(put 'customize-variable 'disabled nil)
