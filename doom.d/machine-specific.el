(add-hook! projectile-mode
;;  (add-to-list 'projectile-project-search-path '("~/Documents/ekata/" . 2))
;;  (add-to-list 'projectile-project-search-path '("~/Documents/me/" . 2))
  )


(setq org-roam-directory "~/Documents/repos/worknotes/org-roam")

;; idk what this is, came with doom

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")

;; c source directory so it doesn't prompt each time
(setq find-function-C-source-directory "~/Documents/repos/etc/emacs/src")
