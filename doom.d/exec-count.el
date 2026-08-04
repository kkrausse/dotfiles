;;; exec-count.el --- count the subprocesses emacs spawns -*- lexical-binding: t; -*-

;; Every exec costs ~265ms on this machine, so "how many processes did that
;; command spawn" matters more than where the CPU went. Not loaded by config.el;
;; `M-x load-file' it when you want to measure.
;;
;;   M-x ec/reset          then do the slow thing
;;   M-x ec/report         who spawned what, worst first

(defvar ec/calls nil "List of (PROGRAM ARG SECONDS).")

(defun ec/reset ()
  "Throw away collected measurements."
  (interactive)
  (setq ec/calls nil)
  (message "exec-count: reset"))

(defun ec/-subcommand (args)
  "First real subcommand in ARGS, skipping flags and `-c key=val' pairs.
Magit prefixes every call with -c core.preloadindex=true and friends, so a
naive \"first non-flag arg\" just reports the config token every time."
  (let ((rest (seq-filter #'stringp args))
        found)
    (while (and rest (not found))
      (let ((a (pop rest)))
        (cond
         ;; -c takes a value in the next arg; drop both
         ((member a '("-c" "-C" "--git-dir" "--work-tree")) (pop rest))
         ((string-prefix-p "-" a))      ; any other flag
         ((string-match-p "=" a))       ; bare key=value
         (t (setq found a)))))
    (or found "")))

(defun ec/-record (program args seconds)
  (push (list (file-name-nondirectory (format "%s" (or program "?")))
              (ec/-subcommand args)
              seconds)
        ec/calls))

(defun ec/-advice (orig program &rest args)
  (let ((start (float-time)))
    (unwind-protect (apply orig program args)
      (ec/-record program args (- (float-time) start)))))

;; Only `call-process'. Do NOT also advise `process-file': it is a lisp function
;; that dispatches to the call-process subr for local files, so advising both
;; counts every local exec twice. (For remote/TRAMP paths process-file does not
;; exec locally at all, so nothing is missed here.)
(advice-add 'call-process :around #'ec/-advice '((name . ec)))
(advice-add 'call-process-region :around
            (lambda (orig start end program &rest args)
              (let ((s (float-time)))
                (unwind-protect (apply orig start end program args)
                  (ec/-record program args (- (float-time) s)))))
            '((name . ec)))

;; make-process takes a plist; pull the command out of it
(defun ec/-make-process-advice (orig &rest plist)
  (let ((cmd (plist-get plist :command))
        (start (float-time)))
    (unwind-protect (apply orig plist)
      (ec/-record (car cmd) (cdr cmd) (- (float-time) start)))))
(advice-add 'make-process :around #'ec/-make-process-advice '((name . ec)))

(defun ec/unhook ()
  "Remove the advice."
  (interactive)
  (dolist (fn '(call-process call-process-region make-process))
    (advice-remove fn 'ec))
  (message "exec-count: unhooked"))

(defun ec/report ()
  "Show what spawned processes, grouped, worst total first."
  (interactive)
  (let ((groups (make-hash-table :test 'equal))
        (total-n 0) (total-s 0.0))
    (dolist (c ec/calls)
      (let* ((key (string-trim (format "%s %s" (nth 0 c) (nth 1 c))))
             (cur (gethash key groups '(0 . 0.0))))
        (puthash key (cons (1+ (car cur)) (+ (cdr cur) (nth 2 c))) groups)
        (setq total-n (1+ total-n)
              total-s (+ total-s (nth 2 c)))))
    (let (rows)
      (maphash (lambda (k v) (push (list k (car v) (cdr v)) rows)) groups)
      (setq rows (sort rows (lambda (a b) (> (nth 2 a) (nth 2 b)))))
      (with-current-buffer (get-buffer-create "*exec-count*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (format "%d execs, %.2fs total\n\n" total-n total-s))
          (insert (format "%6s %9s %9s  %s\n" "count" "total" "each" "command"))
          (dolist (r rows)
            (insert (format "%6d %8.2fs %8.0fms  %s\n"
                            (nth 1 r) (nth 2 r)
                            (* 1000 (/ (nth 2 r) (max 1 (nth 1 r))))
                            (nth 0 r))))
          (goto-char (point-min)))
        (special-mode)
        (display-buffer (current-buffer))))))

(provide 'exec-count)
;;; exec-count.el ends here
