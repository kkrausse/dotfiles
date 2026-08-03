;;; markdown-preview-xwidget.el --- Preview markdown in an xwidget webkit view -*- lexical-binding: t; -*-

;;; Commentary:

;; `kev/markdown-preview-xwidget' renders the current markdown buffer to HTML
;; and displays it in the current window inside an embedded WebKit xwidget, so
;; the preview lives in Emacs instead of an external browser.
;;
;; The HTML is styled from the *live Emacs theme*: background, foreground,
;; links, headings and code-block token colors are all read out of the current
;; faces, so the preview matches whatever theme is loaded.  Code blocks are
;; highlighted with highlight.js, which is downloaded once and then cached
;; locally (see `kev/markdown-preview-xwidget-cache-dir'), so previews keep
;; working offline.
;;
;; Markdown -> HTML conversion reuses `markdown-command', which under Doom is
;; `+markdown-compile' and tries marked, pandoc, markdown and multimarkdown in
;; turn.  At least one of those must be on `exec-path'.
;;
;; Re-running the command refreshes an existing preview rather than opening a
;; second one.  It can also be run from the preview buffer itself, in which case
;; it re-renders the markdown buffer that preview came from.

;;; Code:

(require 'browse-url)
(require 'cl-lib)
(require 'color)
(require 'let-alist)
(require 'subr-x)
(require 'url)
(require 'xwidget)

(defvar markdown-command)
(declare-function markdown-mode "markdown-mode")

(defgroup kev/markdown-preview-xwidget nil
  "Preview markdown buffers in an xwidget webkit view."
  :group 'markdown)

(defcustom kev/markdown-preview-xwidget-highlight-js-base
  "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.11.1/build/"
  "Base URL of the highlight.js distribution used to colorize code blocks.
Assets are downloaded once into `kev/markdown-preview-xwidget-cache-dir'.  If
a download fails the preview still renders, just without token colors."
  :type 'string)

(defcustom kev/markdown-preview-xwidget-extra-languages
  '("lisp" "clojure" "scheme" "dockerfile" "toml")
  "Extra highlight.js language modules to load.
The main highlight.js bundle only ships the \"common\" languages, which
notably excludes Lisp, so `elisp' blocks would otherwise render unhighlighted."
  :type '(repeat string))

(defcustom kev/markdown-preview-xwidget-language-aliases
  '(("lisp" . ("elisp" "emacs-lisp"))
    ("sql" . ("duckdb")))
  "Alist mapping a highlight.js language to extra fence names for it.
Lets info strings that highlight.js does not know, such as the `duckdb'
blocks used by `ob-duckdb', highlight as a language it does know."
  :type '(alist :key-type string :value-type (repeat string)))

(defcustom kev/markdown-preview-xwidget-cache-dir
  (locate-user-emacs-file "markdown-preview-xwidget/")
  "Directory holding cached assets such as the highlight.js bundle."
  :type 'directory)

(defcustom kev/markdown-preview-xwidget-body-font
  "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Helvetica, Arial, sans-serif"
  "CSS font stack used for prose in the preview."
  :type 'string)

(defcustom kev/markdown-preview-xwidget-body-width "46rem"
  "CSS max-width of the rendered document body."
  :type 'string)

(defcustom kev/markdown-preview-xwidget-fallback-to-browser t
  "Whether to fall back to `browse-url' when xwidgets are unavailable.
Xwidgets need a graphical frame, so under `emacs -nw' there is nothing to
embed the WebKit view in.  When this is non-nil the styled HTML opens in the
default browser instead of signaling an error; when nil, the command
signals."
  :type 'boolean)

(defvar-local kev/markdown-preview-xwidget--dir nil
  "Temporary directory holding this buffer's rendered preview.")

(defvar-local kev/markdown-preview-xwidget--counter 0
  "Number of times this buffer has been rendered.
Each render writes a fresh file name so WebKit cannot serve a stale page.")

(defvar-local kev/markdown-preview-xwidget--buffer nil
  "The xwidget buffer currently previewing this markdown buffer.")

(defvar-local kev/markdown-preview-xwidget--source nil
  "In a preview buffer, the markdown buffer it was rendered from.")


;;; Colors

(defun kev/markdown-preview-xwidget--hex (color fallback)
  "Return COLOR as a CSS hex string, or FALLBACK if it is not a real color."
  (let ((rgb (and (stringp color) (color-name-to-rgb color))))
    (if rgb (apply #'color-rgb-to-hex (append rgb '(2))) fallback)))

(defun kev/markdown-preview-xwidget--face (face attr fallback)
  "Return FACE's ATTR as a CSS hex color, following inheritance.
FACE may be a single face or a list of faces to try in order.  FALLBACK is
returned when none of them specify a usable color."
  (let ((faces (if (listp face) face (list face)))
        result)
    (while (and faces (not result))
      (let ((f (pop faces)))
        (when (facep f)
          (let ((color (face-attribute f attr nil t)))
            (when (and (stringp color) (color-name-to-rgb color))
              (setq result (kev/markdown-preview-xwidget--hex color fallback)))))))
    (or result fallback)))

(defun kev/markdown-preview-xwidget--blend (from to alpha fallback)
  "Blend hex colors FROM and TO, keeping ALPHA of FROM.
Return FALLBACK if either color cannot be parsed."
  (let ((a (color-name-to-rgb from))
        (b (color-name-to-rgb to)))
    (if (and a b)
        (apply #'color-rgb-to-hex
               (append (cl-mapcar (lambda (x y) (+ (* alpha x) (* (- 1 alpha) y))) a b)
                       '(2)))
      fallback)))

(defun kev/markdown-preview-xwidget--palette ()
  "Return an alist of CSS colors derived from the current Emacs theme."
  (let* ((bg (kev/markdown-preview-xwidget--face 'default :background "#1c1c1c"))
         (fg (kev/markdown-preview-xwidget--face 'default :foreground "#d8d8d8"))
         ;; Nudge the background toward the foreground for surfaces and rules,
         ;; which keeps contrast sane under both light and dark themes.
         (surface (kev/markdown-preview-xwidget--blend bg fg 0.94 "#252525"))
         (border (kev/markdown-preview-xwidget--blend bg fg 0.80 "#3a3a3a"))
         (muted (kev/markdown-preview-xwidget--face
                 '(shadow font-lock-comment-face) :foreground
                 (kev/markdown-preview-xwidget--blend bg fg 0.45 "#8a8a8a")))
         (accent (kev/markdown-preview-xwidget--face
                  '(link font-lock-function-name-face) :foreground "#5aa7f0")))
    `((bg . ,bg)
      (fg . ,fg)
      (surface . ,surface)
      (border . ,border)
      (muted . ,muted)
      (accent . ,accent)
      (h1 . ,(kev/markdown-preview-xwidget--face '(outline-1 markdown-header-face-1) :foreground fg))
      (h2 . ,(kev/markdown-preview-xwidget--face '(outline-2 markdown-header-face-2) :foreground fg))
      (h3 . ,(kev/markdown-preview-xwidget--face '(outline-3 markdown-header-face-3) :foreground fg))
      (h4 . ,(kev/markdown-preview-xwidget--face '(outline-4 markdown-header-face-4) :foreground fg))
      (h5 . ,(kev/markdown-preview-xwidget--face '(outline-5 markdown-header-face-5) :foreground muted))
      (h6 . ,(kev/markdown-preview-xwidget--face '(outline-6 markdown-header-face-6) :foreground muted))
      (keyword . ,(kev/markdown-preview-xwidget--face 'font-lock-keyword-face :foreground accent))
      (string . ,(kev/markdown-preview-xwidget--face 'font-lock-string-face :foreground "#98c379"))
      (comment . ,(kev/markdown-preview-xwidget--face 'font-lock-comment-face :foreground muted))
      (constant . ,(kev/markdown-preview-xwidget--face 'font-lock-constant-face :foreground "#d19a66"))
      (function . ,(kev/markdown-preview-xwidget--face 'font-lock-function-name-face :foreground accent))
      (variable . ,(kev/markdown-preview-xwidget--face 'font-lock-variable-name-face :foreground fg))
      (type . ,(kev/markdown-preview-xwidget--face 'font-lock-type-face :foreground "#e5c07b"))
      (builtin . ,(kev/markdown-preview-xwidget--face 'font-lock-builtin-face :foreground "#c678dd"))
      (error . ,(kev/markdown-preview-xwidget--face 'error :foreground "#e06c75")))))

(defun kev/markdown-preview-xwidget--code-font ()
  "Return a CSS font stack for code, preferring the current fixed-pitch font.
On a TTY frame the face families are generic placeholders such as
\"Monospace\", which no browser can resolve, so those are skipped."
  (let ((family (face-attribute 'fixed-pitch :family nil t)))
    (concat (if (and (stringp family)
                     (not (member family '("default" "Monospace" "Sans Serif"))))
                (format "\"%s\", " family)
              "")
            "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace")))


;;; CSS

(defun kev/markdown-preview-xwidget--css ()
  "Return the stylesheet for the preview, themed from the current faces."
  (let-alist (kev/markdown-preview-xwidget--palette)
    (format "
:root {
  --bg: %s; --fg: %s; --surface: %s; --border: %s; --muted: %s; --accent: %s;
  --code-font: %s;
}
* { box-sizing: border-box; }
html { background: var(--bg); }
body {
  margin: 0 auto; padding: 3rem 2rem 6rem;
  max-width: %s;
  background: var(--bg); color: var(--fg);
  font-family: %s;
  font-size: 16px; line-height: 1.7;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
::selection { background: var(--accent); color: var(--bg); }

/* Headings */
h1, h2, h3, h4, h5, h6 {
  margin: 2.2em 0 0.7em; line-height: 1.25; font-weight: 650;
}
h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
h1 { font-size: 2.1em; letter-spacing: -0.02em; color: %s;
     padding-bottom: 0.35em; border-bottom: 1px solid var(--border); }
h2 { font-size: 1.55em; letter-spacing: -0.01em; color: %s;
     padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
h3 { font-size: 1.28em; color: %s; }
h4 { font-size: 1.1em; color: %s; }
h5 { font-size: 1em; color: %s; }
h6 { font-size: 0.9em; color: %s; text-transform: uppercase; letter-spacing: 0.06em; }

/* Prose */
p, ul, ol, blockquote, table, pre, dl { margin: 0 0 1.15em; }
a { color: var(--accent); text-decoration: none; border-bottom: 1px solid transparent; }
a:hover { border-bottom-color: var(--accent); }
strong { font-weight: 680; color: %s; }
hr { height: 1px; margin: 2.5em 0; border: 0; background: var(--border); }
img { max-width: 100%%; height: auto; border-radius: 6px; }
ul, ol { padding-left: 1.5em; }
li { margin: 0.3em 0; }
li > ul, li > ol { margin: 0.3em 0; }
li::marker { color: var(--muted); }

blockquote {
  padding: 0.1em 0 0.1em 1.1em;
  border-left: 3px solid var(--border);
  color: var(--muted);
}
blockquote > :last-child { margin-bottom: 0; }

/* Task lists.  The native control is replaced because marked emits it
   disabled, which browsers render as an illegibly dim gray box. */
li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.35em; }
input[type=checkbox] {
  appearance: none; -webkit-appearance: none;
  width: 0.95em; height: 0.95em; margin: 0 0.5em 0 0;
  vertical-align: -0.1em; position: relative;
  background: var(--surface);
  border: 1px solid var(--border); border-radius: 3px;
}
input[type=checkbox]:checked { background: var(--accent); border-color: var(--accent); }
/* Single-quoted so the empty value cannot terminate this Elisp string. */
input[type=checkbox]:checked::after {
  content: ''; position: absolute; left: 0.28em; top: 0.11em;
  width: 0.2em; height: 0.42em;
  border: solid var(--bg); border-width: 0 2px 2px 0;
  transform: rotate(45deg);
}

/* Code */
code, kbd, samp, pre { font-family: var(--code-font); }
code {
  font-size: 0.88em;
  padding: 0.15em 0.4em; border-radius: 4px;
  background: var(--surface); border: 1px solid var(--border);
}
pre {
  padding: 1em 1.1em; border-radius: 8px; overflow-x: auto;
  background: var(--surface); border: 1px solid var(--border);
  line-height: 1.55;
}
pre code {
  font-size: 0.85em;
  padding: 0; border: 0; border-radius: 0; background: none;
}

/* Tables.  `display: block' lets a wide table scroll on its own instead of
   forcing the page sideways; `max-content' keeps it sized to its columns. */
table {
  border-collapse: collapse; font-size: 0.94em;
  display: block; overflow-x: auto;
  width: max-content; max-width: 100%%;
}
th, td { padding: 0.5em 0.85em; border: 1px solid var(--border); text-align: left; }
th { background: var(--surface); font-weight: 650; }
tbody tr:nth-child(even) { background: color-mix(in srgb, var(--surface) 55%%, transparent); }

/* Scrollbars */
::-webkit-scrollbar { width: 11px; height: 11px; }
::-webkit-scrollbar-track { background: var(--bg); }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 6px; border: 2px solid var(--bg); }
::-webkit-scrollbar-thumb:hover { background: var(--muted); }

/* highlight.js tokens, mapped onto font-lock faces */
.hljs-keyword, .hljs-selector-tag, .hljs-doctag, .hljs-name { color: %s; }
.hljs-string, .hljs-regexp, .hljs-addition, .hljs-quote, .hljs-char.escape_ { color: %s; }
.hljs-comment { color: %s; font-style: italic; }
.hljs-number, .hljs-literal, .hljs-selector-attr, .hljs-selector-pseudo { color: %s; }
.hljs-title, .hljs-title.function_, .hljs-section, .hljs-selector-id { color: %s; }
.hljs-variable, .hljs-template-variable, .hljs-attr, .hljs-attribute, .hljs-property, .hljs-params { color: %s; }
.hljs-type, .hljs-title.class_, .hljs-class .hljs-title, .hljs-selector-class { color: %s; }
.hljs-built_in, .hljs-symbol, .hljs-bullet, .hljs-link, .hljs-meta-keyword { color: %s; }
.hljs-meta, .hljs-punctuation { color: %s; }
.hljs-deletion { color: %s; }
.hljs-emphasis { font-style: italic; }
.hljs-strong { font-weight: 700; }
"
            .bg .fg .surface .border .muted .accent
            (kev/markdown-preview-xwidget--code-font)
            kev/markdown-preview-xwidget-body-width
            kev/markdown-preview-xwidget-body-font
            .h1 .h2 .h3 .h4 .h5 .h6
            .fg
            .keyword .string .comment .constant .function .variable .type
            .builtin .comment .error)))


;;; Assets

(defun kev/markdown-preview-xwidget--asset (name url)
  "Return the cached path of asset NAME, fetching it from URL on first use.
Return nil if it is not available, so the caller can degrade gracefully."
  (let ((cache (expand-file-name name kev/markdown-preview-xwidget-cache-dir)))
    (unless (file-exists-p cache)
      (condition-case err
          (progn
            (make-directory (file-name-directory cache) t)
            (message "Downloading %s for markdown preview..." name)
            (url-copy-file url cache t))
        (error
         (message "markdown-preview-xwidget: could not fetch %s (%s)"
                  name (error-message-string err)))))
    (and (file-exists-p cache) cache)))

(defun kev/markdown-preview-xwidget--assets ()
  "Return the highlight.js script files to embed, as a list of paths.
The first element is the core bundle; the rest are extra language modules.
Returns nil when the core bundle is unavailable, since the language modules
are useless without it."
  (let ((core (kev/markdown-preview-xwidget--asset
               "highlight.min.js"
               (concat kev/markdown-preview-xwidget-highlight-js-base
                       "highlight.min.js"))))
    (when core
      (cons core
            (delq nil
                  (mapcar
                   (lambda (lang)
                     (kev/markdown-preview-xwidget--asset
                      (format "lang-%s.min.js" lang)
                      (format "%slanguages/%s.min.js"
                              kev/markdown-preview-xwidget-highlight-js-base
                              lang)))
                   kev/markdown-preview-xwidget-extra-languages))))))

(defun kev/markdown-preview-xwidget--alias-script ()
  "Return JS registering `kev/markdown-preview-xwidget-language-aliases'."
  (mapconcat
   (lambda (entry)
     (format "hljs.registerAliases([%s],{languageName:%S});"
             (mapconcat (lambda (a) (format "%S" a)) (cdr entry) ",")
             (car entry)))
   kev/markdown-preview-xwidget-language-aliases
   ""))


;;; Rendering

(defun kev/markdown-preview-xwidget--convert (beg end out-buffer)
  "Convert markdown between BEG and END into OUT-BUFFER as HTML.
Dispatches on `markdown-command', which may be a function (as under Doom,
where it is `+markdown-compile'), a shell command string, or a list of
program plus arguments."
  (cond
   ((functionp markdown-command)
    (funcall markdown-command beg end out-buffer))
   ((or (stringp markdown-command) (listp markdown-command))
    (let* ((argv (if (listp markdown-command)
                     markdown-command
                   (split-string markdown-command)))
           (program (car argv)))
      (unless (executable-find program)
        (user-error "Markdown command %s not found" program))
      (apply #'call-process-region beg end program nil out-buffer nil (cdr argv))))
   (t (user-error "Invalid `markdown-command': %S" markdown-command))))

(defun kev/markdown-preview-xwidget--absolutize (html dir)
  "Rewrite relative src/href attributes in HTML against DIR.
The preview is rendered from a temporary directory, so relative links to
images and sibling files would otherwise dangle."
  (replace-regexp-in-string
   "\\(\\(?:src\\|href\\)=\\)\"\\([^\"]*\\)\""
   (lambda (match)
     (let ((attr (match-string 1 match))
           (value (match-string 2 match)))
       (if (or (string-empty-p value)
               (string-prefix-p "#" value)
               (string-prefix-p "//" value)
               ;; Already carries a scheme, e.g. https: or mailto:.
               (string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*:" value))
           match
         (concat attr "\"" (browse-url-file-url (expand-file-name value dir)) "\""))))
   html t))

(defun kev/markdown-preview-xwidget--dir ()
  "Return this buffer's preview directory, creating it on first use."
  (unless (and kev/markdown-preview-xwidget--dir
               (file-directory-p kev/markdown-preview-xwidget--dir))
    (setq kev/markdown-preview-xwidget--dir
          (file-name-as-directory (make-temp-file "md-preview-" t)))
    ;; The directory only exists to serve this buffer's preview.
    (add-hook 'kill-buffer-hook
              #'kev/markdown-preview-xwidget--cleanup nil t))
  kev/markdown-preview-xwidget--dir)

(defun kev/markdown-preview-xwidget--cleanup ()
  "Delete the preview directory belonging to the current buffer."
  (when (and kev/markdown-preview-xwidget--dir
             (file-directory-p kev/markdown-preview-xwidget--dir))
    (ignore-errors
      (delete-directory kev/markdown-preview-xwidget--dir t))))

(defun kev/markdown-preview-xwidget--cleanup-all ()
  "Delete every buffer's preview directory.
Buffer-local `kill-buffer-hook' functions do not run when Emacs exits, so
without this the directories would outlive the session."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (kev/markdown-preview-xwidget--cleanup))))

(add-hook 'kill-emacs-hook #'kev/markdown-preview-xwidget--cleanup-all)

(defun kev/markdown-preview-xwidget--render ()
  "Render the current markdown buffer to an HTML file and return its path."
  (let* ((source (current-buffer))
         (dir (kev/markdown-preview-xwidget--dir))
         (base-dir (if buffer-file-name
                       (file-name-directory buffer-file-name)
                     default-directory))
         (title (buffer-name))
         (css (kev/markdown-preview-xwidget--css))
         (scripts (kev/markdown-preview-xwidget--assets))
         (body (with-temp-buffer
                 (let ((out (current-buffer)))
                   (with-current-buffer source
                     ;; Render the whole document even when a region is active,
                     ;; unlike `markdown', which would render just the region.
                     (let ((mark-active nil))
                       (kev/markdown-preview-xwidget--convert
                        (point-min) (point-max) out)))
                   (kev/markdown-preview-xwidget--absolutize
                    (buffer-string) base-dir))))
         ;; A fresh file name per render, so WebKit never serves a cached page.
         (previous (expand-file-name
                    (format "preview-%d.html" kev/markdown-preview-xwidget--counter)
                    dir))
         (file (expand-file-name
                (format "preview-%d.html"
                        (cl-incf kev/markdown-preview-xwidget--counter))
                dir)))
    ;; The scripts are copied next to the HTML and referenced relatively, which
    ;; keeps WebKit from treating them as a cross-directory file:// fetch.
    (dolist (script scripts)
      (copy-file script (expand-file-name (file-name-nondirectory script) dir) t))
    (with-temp-file file
      (set-buffer-file-coding-system 'utf-8-unix)
      (insert "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
              "<meta charset=\"utf-8\">\n"
              "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
              "<title>" (kev/markdown-preview-xwidget--escape title) "</title>\n"
              "<style>" css "</style>\n"
              "</head>\n<body>\n"
              body
              "\n")
      (when scripts
        (dolist (script scripts)
          (insert (format "<script src=\"%s\"></script>\n"
                          (file-name-nondirectory script))))
        (insert "<script>hljs.configure({ignoreUnescapedHTML:true});"
                (kev/markdown-preview-xwidget--alias-script)
                "hljs.highlightAll();</script>\n"))
      (insert "</body>\n</html>\n"))
    (when (file-exists-p previous)
      (ignore-errors (delete-file previous)))
    file))

(defun kev/markdown-preview-xwidget--escape (text)
  "Escape TEXT for inclusion in HTML character data."
  (replace-regexp-in-string
   "[&<>]"
   (lambda (c) (pcase c ("&" "&amp;") ("<" "&lt;") (">" "&gt;")))
   text t t))


;;; Command

;;;###autoload
(defun kev/markdown-preview-xwidget ()
  "Preview the current markdown buffer in an xwidget webkit view.

Convert the buffer to HTML, styled from the current Emacs theme, and show it
in the selected window.  Running the command again refreshes the existing
preview instead of opening another one.  It also works from inside a preview
buffer, where it re-renders the markdown buffer that preview came from.

Xwidgets need a graphical frame.  Under `emacs -nw' the same styled HTML
opens in the default browser instead, unless
`kev/markdown-preview-xwidget-fallback-to-browser' is nil."
  (interactive)
  (require 'markdown-mode)
  (let ((source (cond
                 ((derived-mode-p 'markdown-mode) (current-buffer))
                 ((buffer-live-p kev/markdown-preview-xwidget--source)
                  kev/markdown-preview-xwidget--source)
                 (t (user-error "Not a markdown buffer: %s" major-mode))))
        (blocker (cond
                  ((not (featurep 'xwidget-internal))
                   "this Emacs was not built with xwidget support")
                  ((not (display-graphic-p))
                   "xwidgets need a graphical frame"))))
    (with-current-buffer source
      (let* ((file (kev/markdown-preview-xwidget--render))
             (url (browse-url-file-url file)))
        (when blocker
          (unless kev/markdown-preview-xwidget-fallback-to-browser
            (user-error "Cannot preview: %s" blocker))
          (browse-url url)
          (message "Previewing %s in browser (%s)" (buffer-name source) blocker))
        (unless blocker
          (kev/markdown-preview-xwidget--display source url))))))

(defun kev/markdown-preview-xwidget--display (source url)
  "Show URL in SOURCE's xwidget preview buffer, in the selected window."
  (let* ((preview (with-current-buffer source
                    (and (buffer-live-p kev/markdown-preview-xwidget--buffer)
                         kev/markdown-preview-xwidget--buffer)))
         (session (and preview
                       (with-current-buffer preview
                         (xwidget-at (point-min))))))
    (if session
        (progn
          (xwidget-webkit-goto-uri session url)
          (switch-to-buffer preview))
      ;; `xwidget-webkit-new-session' switches to the new buffer itself, which
      ;; is what puts the preview in the selected window.
      (xwidget-webkit-new-session url)
      (setq preview (xwidget-buffer (xwidget-webkit-last-session))))
    (with-current-buffer source
      (setq kev/markdown-preview-xwidget--buffer preview))
    (with-current-buffer preview
      (setq kev/markdown-preview-xwidget--source source))
    (message "Previewing %s" (buffer-name source))))

(provide 'markdown-preview-xwidget)

;;; markdown-preview-xwidget.el ends here
