;;; magit-git-cache.el --- cache magit's immutable git queries -*- lexical-binding: t; -*-

;; `magit-process-file' is the single chokepoint every synchronous git call in
;; magit goes through, so it is the one place worth patching.
;;
;; It cannot avoid the exec -- see the comment at the bottom -- but a handful of
;; the queries magit repeats are answers that never change for a directory:
;; where the repo root is, where .git is, whether it is bare. Those can be
;; answered from a hash table instead of a 265ms process.
;;
;; Measured on a `magit-refresh' of ~/dotfiles: 21 execs / 5.56s becomes
;; 17 execs / 4.5s. Everything else magit asks (--verify HEAD, --short HEAD,
;; upstream refs) genuinely changes as you commit, so it is not cacheable.

(require 'magit)

(defvar mgc/ttl 300 "Seconds before a cached answer is re-fetched.")
(defvar mgc/cache (make-hash-table :test 'equal))
(defvar mgc/stats (list 0 0) "(HITS MISSES).")

;; Queries whose answer is a property of the directory, not of the history.
(defconst mgc/cacheable
  '("--show-toplevel" "--git-dir" "--is-bare-repository" "--show-cdup")
  "Flags that make a `rev-parse' call safe to cache.")

(defun mgc/flush ()
  "Drop everything cached. Use after moving or re-initializing a repo."
  (interactive)
  (clrhash mgc/cache)
  (setq mgc/stats (list 0 0))
  (message "magit-git-cache: flushed"))

(defun mgc/report ()
  "Show hit/miss counts."
  (interactive)
  (message "magit-git-cache: %d hits, %d misses (~%.1fs saved)"
           (car mgc/stats) (cadr mgc/stats) (* 0.265 (car mgc/stats))))

(defun mgc/-key (args)
  "Cache key for ARGS, or nil if this call must not be cached."
  (and (member "rev-parse" args)
       (let ((flag (seq-find (lambda (a) (member a mgc/cacheable)) args)))
         (and flag (list (expand-file-name default-directory) flag)))))

(defun mgc/-emit (buffer text)
  "Replay cached TEXT into whatever destination BUFFER names."
  (let ((dest (if (consp buffer) (car buffer) buffer)))
    (cond ((null dest) nil)                    ; output discarded
          ((eq dest t) (insert text))           ; current buffer
          ((bufferp dest) (with-current-buffer dest (insert text)))
          ((eq dest 0) nil))))                  ; async/discard

(defun mgc/-advice (orig process &optional infile buffer display &rest args)
  (let ((key (and (equal process (magit-git-executable))
                  (null infile)
                  (mgc/-key args))))
    (if (not key)
        (apply orig process infile buffer display args)
      (let ((hit (gethash key mgc/cache)))
        (if (and hit (< (- (float-time) (nth 2 hit)) mgc/ttl))
            (progn
              (cl-incf (car mgc/stats))
              (mgc/-emit buffer (nth 1 hit))
              (nth 0 hit))
          ;; miss: run it for real, capturing what it wrote so we can replay it
          (cl-incf (cadr mgc/stats))
          (let* ((tmp (generate-new-buffer " *mgc*"))
                 (code (unwind-protect
                           (apply orig process infile (list tmp nil) display args)
                         nil))
                 (text (with-current-buffer tmp (buffer-string))))
            (kill-buffer tmp)
            (puthash key (list code text (float-time)) mgc/cache)
            (mgc/-emit buffer text)
            code))))))

(advice-add 'magit-process-file :around #'mgc/-advice '((name . mgc)))

(defun mgc/uninstall ()
  (interactive)
  (advice-remove 'magit-process-file 'mgc)
  (mgc/flush))

;; Why this cannot go further: running git's code requires loading git's binary,
;; which is what exec *is* -- fork only duplicates the program already running.
;; So there is no "exec that is really a fork". The only ways to answer a git
;; question without exec are to link libgit2 into emacs (magit-libgit, which
;; covers almost nothing and is not built here) or to keep one git process alive
;; serving many queries -- which git only supports for a few plumbing commands
;; (cat-file --batch, check-attr --stdin), none of which are what magit needs.

(provide 'magit-git-cache)
;;; magit-git-cache.el ends here
