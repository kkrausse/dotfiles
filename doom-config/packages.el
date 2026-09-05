;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or
;; use 'M-x doom/reload'.


;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;(package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/raxod502/straight.el#the-recipe-format
;(package! another-package
;  :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;(package! this-package
;  :recipe (:host github :repo "username/repo"
;           :files ("some-file.el" "src/lisp/*.el")))


;; fuck this thing
(package! clj-refactor :disable 1)
;; this package is satan's child I swear
;; (package! better-jumper :disable 1)

(package! dired-du)
(package! doom-themes)
;; for "jj" chord binding to escape
(package! key-chord)
(package! evil-escape)

;; logging
(package! command-log-mode)

;; make it so terminal colors arent shit
(package! solaire-mode :disable t)

;; fixing this to use newer github stuff
;; it seems they keep this up to date in melpa?
;; (package! lsp-mode)
;; (package! lsp-ui)

;; override those in the clojure doom module
;; pinning these have fucked me before
;;  switch add `:pin nil' if ya want
;; (package! clojure-mode :disable 1)

;; nice partial screens for org roam
(package! visual-fill-column
  :recipe (:host nil
           :repo "https://codeberg.org/joostkremers/visual-fill-column"))

(package! exec-path-from-shell
  :recipe (:host github
           :repo "purcell/exec-path-from-shell"
           :branch "master"))

(package! ellama
  :recipe (:host github
           :repo "s-kostyaev/ellama"
           :branch "main"))

(package! restclient
  :recipe (:host github
           :repo "pashky/restclient.el"
           :branch "master"))

(package! browse-at-remote
  ;; :pin "cef26f2c063f2473af42d0e126c8613fe2f709e4"
  :recipe (:host github
           :repo "rmuslimov/browse-at-remote"
           :branch "master"))

;; (package! company
;;   :recipe (:host github
;;            :repo "company-mode/company-mode"
;;            :branch "master"))

(package! org-roam
  ;; taken from repo
  :recipe (:host github :repo "org-roam/org-roam"
           :files (:defaults "extensions/*")
           ;; do this if modifying locally
           ;; :build (:not compile)
           ))

;; dont think this is needed bc of doom?
;; (package! jet
;;   :recipe (:type git
;;            :host nil
;;            :branch "master"
;;            :repo "https://github.com/ericdallo/jet.el"))

(package! org-bullets)

;; navigation?
(package! elisp-slime-nav)
(package! zoom)
(package! smartparens)
(package! aggressive-indent-mode)
(package! evil-smartparens)

;; for bibtex references
(package! org-ref
  :recipe (:type git
           :host nil
           :repo "https://github.com/jkitchin/org-ref.git" ))

(package! org-roam-bibtex
  :pin "f90ac12b7ae5ba7bcdebfe53796fd0417946e5e1"
  :recipe (:type git
           :host nil
           :repo "https://github.com/org-roam/org-roam-bibtex.git"))

(package! citar-org-roam
  :pin "4f02b3b15fe06dfa19482e72b4efc3d0aa0d5b85"
  :recipe (:type git
           :host nil
           :repo "https://github.com/emacs-citar/citar-org-roam.git"))

(package! csv-mode)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;(package! builtin-package :recipe (:nonrecursive t))
;(package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see raxod502/straight.el#279)
;(package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;(package! builtin-package :pin "1a2b3c4d5e")


;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;(unpin! pinned-package)
;; ...or multiple packages
;(unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;(unpin! t)
