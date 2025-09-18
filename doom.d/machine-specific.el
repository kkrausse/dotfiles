(add-hook! projectile-mode
 (add-to-list 'projectile-project-search-path '("~/Documents/" . 3))
;;  (add-to-list 'projectile-project-search-path '("~/Documents/me/" . 2))
  )


(setq kev/py-shell-interpreter "/Users/kevinkrausse/miniconda/envs/base2/bin/python")
(setq org-roam-directory "/Users/kevinkrausse/Documents/repos/worknotes/org-roam")
(setq org-roam-db-location "/Users/kevinkrausse/.config/emacs/.local/cache/org-roam.db")
(setq org-roam-dailies-directory "taxbit-daily/")

;; idk what this is, came with doom

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


(defun edit-env-file ()
  (interactive)
  (find-file "~/kevenv.sh"))
