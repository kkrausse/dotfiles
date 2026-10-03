;;; markdown-preview-xwidget.el --- Preview markdown in an xwidget webkit view -*- lexical-binding: t; -*-

;;; Commentary:

;; `kev/markdown-preview-xwidget' renders the current markdown buffer to HTML
;; and displays it in the current window inside an embedded WebKit xwidget, so
;; the preview lives in Emacs instead of an external browser.
;;
;; `kev/markdown-preview-in-browser' renders the same HTML but hands it to
;; `browse-url', for when the real browser is wanted instead: devtools, a
;; second monitor, printing, or an Emacs without xwidget support.
;;
;; Two looks are available, chosen with `kev/markdown-preview-xwidget-style':
;;
;; - `github' (the default) renders a GitHub-style document card on an inset
;;   page, using Primer's palette.  This is what the `grip' setup in
;;   ~/.grip looks like.  Light or dark follows the Emacs theme's background
;;   unless `kev/markdown-preview-xwidget-appearance' overrides it.
;;
;; - `emacs' derives every color from the *live Emacs theme*: background,
;;   foreground, links, headings and code tokens all read out of the current
;;   faces.  A saturated syntax theme makes for saturated prose, which is why
;;   it is no longer the default.
;;
;; Code blocks are highlighted with highlight.js, which is downloaded once and
;; then cached locally (see `kev/markdown-preview-xwidget-cache-dir'), so
;; previews keep working offline.
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
(require 'subr-x)
(require 'url)
(require 'xwidget)

(defvar markdown-command)
(declare-function markdown-mode "markdown-mode")

(defgroup kev/markdown-preview-xwidget nil
  "Preview markdown buffers in an xwidget webkit view."
  :group 'markdown)

(defcustom kev/markdown-preview-xwidget-style 'github
  "Which look the preview is rendered in.
`github' uses Primer's document palette and a centered card, matching the
grip setup in ~/.grip.  `emacs' derives every color from the faces of the
currently loaded theme."
  :type '(choice (const :tag "GitHub / Primer" github)
                 (const :tag "Current Emacs theme" emacs)))

(defcustom kev/markdown-preview-xwidget-appearance 'auto
  "Light or dark for the `github' style.
`auto' follows the luminance of the `default' face background, so the preview
flips with the Emacs theme.  Has no effect on the `emacs' style, which takes
its background from the theme directly."
  :type '(choice (const :tag "Follow the Emacs theme" auto)
                 (const :tag "Always light" light)
                 (const :tag "Always dark" dark)))

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
  "CSS max-width of prose in the rendered document."
  :type 'string)

(defcustom kev/markdown-preview-xwidget-wide-width "78rem"
  "CSS max-width of wide blocks -- tables and code -- in the rendered document.
Prose keeps `kev/markdown-preview-xwidget-body-width'; blocks that read badly
when squeezed are allowed out to this width instead.  Set it equal to the body
width to put every block back on one measure."
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

(defun kev/markdown-preview-xwidget--dark-p ()
  "Non-nil when the `github' style should use its dark palette.
Under `auto' this is decided by the perceived brightness of the `default'
face background, so the preview flips with the Emacs theme."
  (pcase kev/markdown-preview-xwidget-appearance
    ('light nil)
    ('dark t)
    (_ (let ((rgb (color-name-to-rgb
                   (face-attribute 'default :background nil t))))
         (if rgb
             (< (+ (* 0.2126 (nth 0 rgb)) (* 0.7152 (nth 1 rgb))
                   (* 0.0722 (nth 2 rgb)))
                0.5)
           (eq (frame-parameter nil 'background-mode) 'dark))))))

;; Primer's document colors, the same ones GitHub itself renders READMEs with,
;; plus the highlight.js github/github-dark token colors.  Hard-coded rather
;; than derived: these are picked for reading long prose, which is not what a
;; syntax theme's palette is for.
(defconst kev/markdown-preview-xwidget--github-light
  '((bg . "#ffffff") (canvas . "#f6f8fa") (surface . "#f6f8fa")
    (border . "#d1d9e0") (border-muted . "#d8dee4")
    (fg . "#1f2328") (muted . "#59636e") (accent . "#0969da")
    (strong . "#1f2328")
    (h1 . "#1f2328") (h2 . "#1f2328") (h3 . "#1f2328")
    (h4 . "#1f2328") (h5 . "#1f2328") (h6 . "#59636e")
    (code-keyword . "#cf222e") (code-string . "#0a3069")
    (code-comment . "#6e7781") (code-number . "#0550ae")
    (code-title . "#8250df") (code-variable . "#953800")
    (code-builtin . "#953800") (code-type . "#cf222e")
    (code-name . "#116329") (code-bullet . "#4d2d00")
    (code-addition . "#116329") (code-addition-bg . "#dafbe1")
    (code-deletion . "#82071e") (code-deletion-bg . "#ffebe9"))
  "Primer light palette for the `github' style.")

(defconst kev/markdown-preview-xwidget--github-dark
  '((bg . "#0d1117") (canvas . "#010409") (surface . "#151b23")
    (border . "#3d444d") (border-muted . "#2f353d")
    (fg . "#f0f6fc") (muted . "#9198a1") (accent . "#4493f8")
    (strong . "#f0f6fc")
    (h1 . "#f0f6fc") (h2 . "#f0f6fc") (h3 . "#f0f6fc")
    (h4 . "#f0f6fc") (h5 . "#f0f6fc") (h6 . "#9198a1")
    (code-keyword . "#ff7b72") (code-string . "#a5d6ff")
    (code-comment . "#8b949e") (code-number . "#79c0ff")
    (code-title . "#d2a8ff") (code-variable . "#ffa657")
    (code-builtin . "#ffa657") (code-type . "#ff7b72")
    (code-name . "#7ee787") (code-bullet . "#f2cc60")
    (code-addition . "#aff5b4") (code-addition-bg . "#033a16")
    (code-deletion . "#ffdcd7") (code-deletion-bg . "#67060c"))
  "Primer dark palette for the `github' style.")

(defun kev/markdown-preview-xwidget--emacs-palette ()
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
                  '(link font-lock-function-name-face) :foreground "#5aa7f0"))
         (string (kev/markdown-preview-xwidget--face
                  'font-lock-string-face :foreground "#98c379"))
         (err (kev/markdown-preview-xwidget--face 'error :foreground "#e06c75")))
    `((bg . ,bg)
      ;; Flat page: the card carries no contrast under this style.
      (canvas . ,bg)
      (surface . ,surface)
      (border . ,border)
      (border-muted . ,border)
      (fg . ,fg)
      (muted . ,muted)
      (accent . ,accent)
      (strong . ,fg)
      (h1 . ,(kev/markdown-preview-xwidget--face '(outline-1 markdown-header-face-1) :foreground fg))
      (h2 . ,(kev/markdown-preview-xwidget--face '(outline-2 markdown-header-face-2) :foreground fg))
      (h3 . ,(kev/markdown-preview-xwidget--face '(outline-3 markdown-header-face-3) :foreground fg))
      (h4 . ,(kev/markdown-preview-xwidget--face '(outline-4 markdown-header-face-4) :foreground fg))
      (h5 . ,(kev/markdown-preview-xwidget--face '(outline-5 markdown-header-face-5) :foreground muted))
      (h6 . ,(kev/markdown-preview-xwidget--face '(outline-6 markdown-header-face-6) :foreground muted))
      (code-keyword . ,(kev/markdown-preview-xwidget--face 'font-lock-keyword-face :foreground accent))
      (code-string . ,string)
      (code-comment . ,(kev/markdown-preview-xwidget--face 'font-lock-comment-face :foreground muted))
      (code-number . ,(kev/markdown-preview-xwidget--face 'font-lock-constant-face :foreground "#d19a66"))
      (code-title . ,(kev/markdown-preview-xwidget--face 'font-lock-function-name-face :foreground accent))
      (code-variable . ,(kev/markdown-preview-xwidget--face 'font-lock-variable-name-face :foreground fg))
      (code-builtin . ,(kev/markdown-preview-xwidget--face 'font-lock-builtin-face :foreground "#c678dd"))
      (code-type . ,(kev/markdown-preview-xwidget--face 'font-lock-type-face :foreground "#e5c07b"))
      (code-name . ,(kev/markdown-preview-xwidget--face 'font-lock-keyword-face :foreground accent))
      (code-bullet . ,muted)
      (code-addition . ,string)
      (code-addition-bg . ,(kev/markdown-preview-xwidget--blend string bg 0.15 surface))
      (code-deletion . ,err)
      (code-deletion-bg . ,(kev/markdown-preview-xwidget--blend err bg 0.15 surface)))))

(defun kev/markdown-preview-xwidget--palette ()
  "Return the alist of CSS colors for `kev/markdown-preview-xwidget-style'."
  (if (eq kev/markdown-preview-xwidget-style 'emacs)
      (kev/markdown-preview-xwidget--emacs-palette)
    (if (kev/markdown-preview-xwidget--dark-p)
        kev/markdown-preview-xwidget--github-dark
      kev/markdown-preview-xwidget--github-light)))

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

(defun kev/markdown-preview-xwidget--css-vars ()
  "Return a `:root' block declaring every custom property the sheet uses.
Keeping the palette here means the stylesheet below is a plain string with no
interpolation, so it can be edited as ordinary CSS."
  (concat
   ":root {\n"
   (mapconcat (lambda (cell) (format "  --%s: %s;" (car cell) (cdr cell)))
              (append (kev/markdown-preview-xwidget--palette)
                      `((code-font . ,(kev/markdown-preview-xwidget--code-font))
                        (body-font . ,kev/markdown-preview-xwidget-body-font)
                        (measure . ,kev/markdown-preview-xwidget-body-width)
                        (wide . ,kev/markdown-preview-xwidget-wide-width)))
              "\n")
   "\n}\n"))

(defconst kev/markdown-preview-xwidget--base-css "
* { box-sizing: border-box; }
html { background: var(--canvas); }
body {
  margin: 0; padding: 0;
  background: var(--canvas); color: var(--fg);
  font-family: var(--body-font);
  font-size: 16.5px; line-height: 1.7;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
/* The body column is as wide as the widest block may get; prose is centered
   back down to the reading measure, so a wide table is not crushed into it. */
.doc-body { max-width: var(--wide); margin: 0 auto; }
.doc-body > :is(h1, h2, h3, h4, h5, h6, p, ul, ol, dl, blockquote, hr,
                figure, details, img) {
  max-width: var(--measure); margin-left: auto; margin-right: auto;
}
.doc-body > :first-child { margin-top: 0; }
.doc-body > :last-child { margin-bottom: 0; }
::selection { background: var(--accent); color: var(--bg); }

/* Headings */
h1, h2, h3, h4, h5, h6 {
  margin: 2em 0 0.65em; line-height: 1.3; font-weight: 600;
  letter-spacing: -0.011em;
}
h1 { font-size: 1.9em; color: var(--h1);
     padding-bottom: 0.35em; border-bottom: 1px solid var(--border-muted); }
h2 { font-size: 1.4em; color: var(--h2); margin-top: 2.2em;
     padding-bottom: 0.3em; border-bottom: 1px solid var(--border-muted); }
h3 { font-size: 1.15em; color: var(--h3); }
h4 { font-size: 1em; color: var(--h4); }
h5 { font-size: 0.9em; color: var(--h5); }
h6 { font-size: 0.85em; color: var(--h6); text-transform: uppercase; letter-spacing: 0.06em; }

/* Prose */
p, ul, ol, blockquote, table, pre, dl { margin: 0 0 1.1em; }
a { color: var(--accent); text-decoration: none; text-underline-offset: 0.2em; }
a:hover { text-decoration: underline; }
strong { font-weight: 600; color: var(--strong); }
hr { height: 1px; margin: 2.5em 0; border: 0; background: var(--border-muted); }
img { max-width: 100%; height: auto; border-radius: 6px; }
ul, ol { padding-left: 1.6em; }
li + li { margin-top: 0.3em; }
li > ul, li > ol { margin: 0.3em 0; }
li::marker { color: var(--muted); }

blockquote {
  padding: 0.1em 0 0.1em 1.1em;
  border-left: 3px solid var(--accent);
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
  background: var(--bg);
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
:not(pre) > code {
  font-size: 0.84em;
  padding: 0.18em 0.38em; border-radius: 5px; white-space: nowrap;
  background: var(--surface); border: 1px solid var(--border-muted);
}
pre {
  padding: 1rem 1.15rem; border-radius: 8px; overflow-x: auto;
  background: var(--surface); border: 1px solid var(--border-muted);
  font-size: 0.84em; line-height: 1.55;
}
pre code { padding: 0; border: 0; border-radius: 0; background: none; }

/* Tables.  The wrapper scrolls a wide table on its own instead of forcing the
   whole page sideways; `overflow: hidden' is what rounds the corners. */
table {
  border-collapse: collapse; font-size: 0.94em;
  display: block; overflow: auto;
  width: max-content; max-width: 100%;
  margin: 1.4em 0;
  border: 1px solid var(--border); border-radius: 8px;
}
th, td {
  padding: 0.55rem 0.85rem; text-align: left;
  border: 0; border-bottom: 1px solid var(--border-muted);
}
th {
  background: var(--surface); color: var(--muted);
  font-size: 0.82em; font-weight: 600;
  text-transform: uppercase; letter-spacing: 0.04em;
}
tbody tr:nth-child(even) { background: var(--surface); }
tbody tr:last-child td { border-bottom: 0; }

/* Scrollbars */
::-webkit-scrollbar { width: 11px; height: 11px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--border); border-radius: 6px; border: 2px solid var(--bg); }
::-webkit-scrollbar-thumb:hover { background: var(--muted); }

/* highlight.js tokens */
.hljs-keyword, .hljs-doctag, .hljs-template-tag, .hljs-template-variable,
.hljs-variable.language_ { color: var(--code-keyword); }
.hljs-type, .hljs-title.class_, .hljs-class .hljs-title { color: var(--code-type); }
.hljs-title, .hljs-title.function_, .hljs-section { color: var(--code-title); }
.hljs-attr, .hljs-attribute, .hljs-literal, .hljs-number, .hljs-operator,
.hljs-variable, .hljs-selector-attr, .hljs-selector-class,
.hljs-selector-id { color: var(--code-number); }
.hljs-string, .hljs-regexp, .hljs-char.escape_ { color: var(--code-string); }
.hljs-built_in, .hljs-symbol { color: var(--code-builtin); }
.hljs-name, .hljs-quote, .hljs-selector-tag, .hljs-selector-pseudo { color: var(--code-name); }
.hljs-comment, .hljs-code, .hljs-formula { color: var(--code-comment); font-style: italic; }
.hljs-meta, .hljs-punctuation { color: var(--muted); }
.hljs-bullet, .hljs-link { color: var(--code-bullet); }
.hljs-addition { color: var(--code-addition); background: var(--code-addition-bg); }
.hljs-deletion { color: var(--code-deletion); background: var(--code-deletion-bg); }
.hljs-emphasis { font-style: italic; }
.hljs-strong { font-weight: 700; }

/* Print / PDF export from the browser preview. */
@media print {
  html, body { background: #fff; }
  .doc { border: 0; box-shadow: none; }
  .doc-header { display: none; }
  .doc-body { padding: 0; }
  pre, table { break-inside: avoid; }
  h1, h2, h3 { break-after: avoid; }
}
"
  "Typography, code and table rules, shared by every style.")

(defconst kev/markdown-preview-xwidget--github-frame-css "
/* A GitHub README: one bordered card floating on an inset page. */
.page { padding: 2rem 1.5rem 4rem; }
.doc {
  max-width: calc(var(--wide) + 6rem);
  margin: 0 auto;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 1px 3px rgba(0,0,0,.06), 0 8px 24px rgba(0,0,0,.04);
}
.doc-header {
  padding: 0.6rem 1.25rem;
  border-bottom: 1px solid var(--border);
  font-family: var(--code-font);
  font-size: 12px; font-weight: 500; letter-spacing: 0.02em;
  color: var(--muted);
}
.doc-body { padding: 2.5rem clamp(1.25rem, 5vw, 3rem) 3.5rem; }
"
  "Card frame for the `github' style.")

(defconst kev/markdown-preview-xwidget--emacs-frame-css "
/* Flat page: the Emacs theme already supplies the only background there is. */
.page { padding: 0; }
.doc { background: var(--bg); }
.doc-header { display: none; }
.doc-body { padding: 3rem 2rem 6rem; }
"
  "Flat frame for the `emacs' style.")

(defun kev/markdown-preview-xwidget--css ()
  "Return the stylesheet for the preview."
  (concat (kev/markdown-preview-xwidget--css-vars)
          kev/markdown-preview-xwidget--base-css
          (if (eq kev/markdown-preview-xwidget-style 'emacs)
              kev/markdown-preview-xwidget--emacs-frame-css
            kev/markdown-preview-xwidget--github-frame-css)))


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

(defun kev/markdown-preview-xwidget--render (&optional name)
  "Render the current markdown buffer to an HTML file and return its path.
With NAME, write to that file name in the buffer's preview directory, giving
the file a stable URL across renders so an already-open page can just be
reloaded.  Without it, each render writes a fresh name and deletes the
previous one, which is what keeps WebKit from serving a stale page."
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
         (previous (and (null name)
                        (expand-file-name
                         (format "preview-%d.html"
                                 kev/markdown-preview-xwidget--counter)
                         dir)))
         (file (expand-file-name
                (or name
                    (format "preview-%d.html"
                            (cl-incf kev/markdown-preview-xwidget--counter)))
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
              "<div class=\"page\">\n<article class=\"doc\">\n"
              "<header class=\"doc-header\">"
              (kev/markdown-preview-xwidget--escape title)
              "</header>\n<div class=\"doc-body\">\n"
              body
              "\n</div>\n</article>\n</div>\n")
      (when scripts
        (dolist (script scripts)
          (insert (format "<script src=\"%s\"></script>\n"
                          (file-name-nondirectory script))))
        (insert "<script>hljs.configure({ignoreUnescapedHTML:true});"
                (kev/markdown-preview-xwidget--alias-script)
                "hljs.highlightAll();</script>\n"))
      (insert "</body>\n</html>\n"))
    (when (and previous (file-exists-p previous))
      (ignore-errors (delete-file previous)))
    file))

(defun kev/markdown-preview-xwidget--escape (text)
  "Escape TEXT for inclusion in HTML character data."
  (replace-regexp-in-string
   "[&<>]"
   (lambda (c) (pcase c ("&" "&amp;") ("<" "&lt;") (">" "&gt;")))
   text t t))


;;; Commands

(defun kev/markdown-preview-xwidget--source-buffer ()
  "Return the markdown buffer to preview, signaling if there is none.
That is the current buffer when it is a markdown buffer, and in a preview
buffer the markdown buffer that preview was rendered from."
  (cond
   ((derived-mode-p 'markdown-mode) (current-buffer))
   ((buffer-live-p kev/markdown-preview-xwidget--source)
    kev/markdown-preview-xwidget--source)
   (t (user-error "Not a markdown buffer: %s" major-mode))))

;;;###autoload
(defun kev/markdown-preview-xwidget ()
  "Preview the current markdown buffer in an xwidget webkit view.

Convert the buffer to HTML, styled from the current Emacs theme, and show it
in the selected window.  Running the command again refreshes the existing
preview instead of opening another one.  It also works from inside a preview
buffer, where it re-renders the markdown buffer that preview came from.

Xwidgets need a graphical frame.  Under `emacs -nw' the same styled HTML
opens in the default browser instead, unless
`kev/markdown-preview-xwidget-fallback-to-browser' is nil.  To always use the
browser, see `kev/markdown-preview-in-browser'."
  (interactive)
  (require 'markdown-mode)
  (let ((source (kev/markdown-preview-xwidget--source-buffer))
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

;;;###autoload
(defun kev/markdown-preview-in-browser ()
  "Preview the current markdown buffer in the default browser.

Render exactly what `kev/markdown-preview-xwidget' renders -- the same HTML,
themed from the current Emacs theme -- and open it with `browse-url' instead
of embedding it in a WebKit xwidget.  Like the xwidget command, this also
works from inside a preview buffer, re-rendering the markdown buffer that
preview came from.

The page keeps a stable URL per markdown buffer, so after re-running this
command an already-open tab can simply be reloaded.  The file lives in a
temporary directory that is deleted when the markdown buffer is killed or
Emacs exits, after which the tab has nothing left to reload."
  (interactive)
  (require 'markdown-mode)
  (let ((source (kev/markdown-preview-xwidget--source-buffer)))
    (with-current-buffer source
      (let ((file (kev/markdown-preview-xwidget--render "preview.html")))
        (browse-url (browse-url-file-url file))
        (message "Previewing %s in browser" (buffer-name source))))))

(provide 'markdown-preview-xwidget)

;;; markdown-preview-xwidget.el ends here
