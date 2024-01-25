;; doom-vibrant-theme.el --- a more vibrant version of doom-one -*- no-byte-compile: t; -*-
(require 'doom-themes)

;;
(defgroup kev-doom-vibrant-theme nil
  "Options for doom-themes"
  :group 'doom-themes)

(defcustom kev-doom-vibrant-brighter-modeline nil
  "If non-nil, more vivid colors will be used to style the mode-line."
  :group 'kev-doom-vibrant-theme
  :type 'boolean)

(defcustom kev-doom-vibrant-brighter-comments nil
  "If non-nil, comments will be highlighted in more vivid colors."
  :group 'kev-doom-vibrant-theme
  :type 'boolean)

(defcustom kev-doom-vibrant-comment-bg kev-doom-vibrant-brighter-comments
  "If non-nil, comments will have a subtle, darker background. Enhancing their
legibility."
  :group 'kev-doom-vibrant-theme
  :type 'boolean)

(defcustom kev-doom-vibrant-padded-modeline doom-themes-padded-modeline
  "If non-nil, adds a 4px padding to the mode-line. Can be an integer to
determine the exact padding."
  :group 'kev-doom-vibrant-theme
  :type '(choice integer boolean))


(def-doom-theme my-vibrant
  "A dark theme based off of doom-one with more vibrant colors."

  ;; name        gui       256       16
  ((bg         '("grey7"   "grey7"  nil)) ;;
   (bg-alt     '("grey15"  "grey15"  nil)) ;; current line hightlighted & dired
   (base0      '("#1c1f24" "#101010" "black"        ))
   (base1      '("#1c1f24" "#1e1e1e" "brightblack"  ))
   (base2      '("#21272d" "#21212d" "brightblack"  ))
   (base3      '("#23272e" "#262626" "brightblack"  ))
   (base4      '("#484854" "#5e5e5e" "brightblack"  ))
   (base5      '("#62686E" "#666666" "brightblack"  ))
   (base6      '("#757B80" "#7b7b7b" "brightblack"  ))
   (base7      '("#9ca0a4" "#979797" "brightblack"  ))
   (base8      '("#DFDFDF" "#dfdfdf" "white"        ))
   (fg         '("grey70" "grey70" ))
   (fg-alt     '("grey85" "grey85" ))
   ;;(fg         '("grey70" "grey70" ))
   ;;(fg-alt     '("grey85" "grey85" ))

   (grey       base4)
   (red        '("#ed5147" "#ff6655" ))
   (orange     '("#e69055" "#dd8844" ))
   (green      '("#3bd188" "#99bb66" ))
   (dark-green '("#01753b" "#01753b" ))
   (teal       '("#4db5bd" "#44b9b1" ))
   (yellow     '("#FCCE7B"           ))
   (blue       '("#7A7AFF"           ))
   (dark-blue  '("#1f5582"           ))
   (magenta    '("#db7b9e"           ))
   (violet     '("#d481d0"           )) ;a9a1e1
   (cyan       '("#5cEfFF"           ))
   (dark-cyan  '("#6A8FBF"           ))

   ;; remoinder that color wheel is:
   ;; rgb
   ;; yellow = r + g
   ;; cyan = g + b
   ;; magenta = r + b
   ;;
   ;; r-g colorblind means focus on the blue-yellow axis more
   ;;
   ;; face categories
   (highlight      blue)
   (vertical-bar   base0)
   (selection      dark-blue)
   (builtin        magenta)
   (comments       (doom-darken dark-cyan 0.1)) ;; was base5
   (doc-comments   magenta)
   (constants      violet)
   (keywords       orange)
   (functions      blue)
   (methods        cyan)
   (operators      blue) ;; was blue
   (type           (doom-darken yellow 0.1))
   (strings        (doom-darken green 0.1))
   (variables      teal)
   (numbers        orange)
   (region         base4)
   (error          red)
   (warning        yellow)
   (success        green)
   (vc-modified    yellow)
   (vc-added       green)
   (vc-deleted     red)

   ;; custom categories
   (hidden     bg)
   (hidden-alt bg-alt)
   (-modeline-pad 1)

   ;; File-name
;;   (doom-modeline-project-dir :bold t :foreground cyan)
;;   (doom-modeline-buffer-path :inherit 'bold :foreground green)
;;   (doom-modeline-buffer-file :inherit 'bold :foreground fg)
;;   (doom-modeline-buffer-modified :inherit 'bold :foreground yellow)
   ;; ;; Misc
   ;; (doom-modeline-error :background bg)
   ;; (doom-modeline-buffer-major-mode :foreground green :bold t)
   ;; (doom-modeline-info :bold t :foreground cyan)
   ;; (doom-modeline-bar :background (doom-darken green 0.2))
   ;; (doom-modeline-panel :background (doom-darken green 0.2) :foreground fg)


   (modeline-fg     fg-alt)
   (modeline-fg-alt (doom-blend blue grey 0.2))

   (modeline-bg bg-alt)

   (modeline-bg-l modeline-bg)
   (modeline-bg-inactive   (doom-darken bg 0.25))
   (modeline-bg-inactive-l `(,(doom-darken (car bg-alt) 0.2) ,@(cdr base0))))

  ;; --- extra faces ------------------------
  (((all-the-icons-dblue &override) :foreground dark-cyan)
   (centaur-tabs-unselected :background bg-alt :foreground base6)
   (elscreen-tab-other-screen-face :background "#353a42" :foreground "#1e2022")

   ;; lisp
   (highlight-quoted-symbol :foreground (doom-darken yellow 0.15))

   ;;;;;;;; Editor ;;;;;;;;
   (cursor :background fg-alt)
   (hl-line :background (doom-darken red 0.7))

   ;;;;;;;; Brackets ;;;;;;;;
   ;; Rainbow-delimiters

   (rainbow-delimiters-depth-1-face :foreground (doom-lighten red 0.5))
   (rainbow-delimiters-depth-2-face :foreground yellow)
   (rainbow-delimiters-depth-3-face :foreground (doom-lighten cyan 0.2))
   (rainbow-delimiters-depth-4-face :foreground (doom-lighten red 0.5))
   (rainbow-delimiters-depth-5-face :foreground yellow)
   (rainbow-delimiters-depth-6-face :foreground cyan)
   (rainbow-delimiters-depth-3-face :foreground (doom-lighten cyan 0.2))
   (rainbow-delimiters-depth-4-face :foreground (doom-lighten red 0.5))
   ;; Bracket pairing
   ((show-paren-match &override) :foreground nil :background base5 :bold t)
   ((show-paren-mismatch &override) :foreground nil :background "red")

   ;; from
   (dired-directory :foreground cyan :background bg-alt)
   (dired-marked :foreground yellow)
   (dired-symlink :foreground cyan)
   (dired-header :foreground cyan)

   (font-lock-comment-face
    :foreground comments
    :background (if kev-doom-vibrant-comment-bg (doom-darken bg-alt 0.095)))
   (font-lock-doc-face
    :inherit 'font-lock-comment-face
    :foreground doc-comments)

   ((line-number &override) :foreground base4)
   ((line-number-current-line &override) :foreground blue :bold bold)

   (doom-modeline-bar :background modeline-bg)
   (doom-modeline-buffer-path :foreground base8 :bold bold)

   ;; omg this was such a pita
   ((orderless-match-face-0 &override) :foreground base1)
   ((orderless-match-face-1 &override) :foreground base1)
   ((orderless-match-face-2 &override) :foreground base1)
   ((orderless-match-face-3 &override) :foreground base1)
   (custom-modified :foreground red :background yellow)
   (custom-modified :foreground red :background yellow)
   ((custom-modified &override) :foreground red :background (doom-blend blue bg 0.5))
   ((completions-common-part &override) :background red :inherit 'evil-ex-lazy-highlight)
   ((completions-first-difference &override) :background red :inherit 'evil-ex-lazy-highlight)
  ;;  (evil-ex-lazy-highlight :background (doom-darken cyan 0.3) :inherit 'shadow)
   (mode-line
    :background modeline-bg :foreground modeline-fg
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-darken blue 0.6)))
    :height 0.9)
   (mode-line-inactive
    :background modeline-bg-inactive :foreground modeline-fg-alt
    :box (if -modeline-pad `(:line-width ,-modeline-pad :color ,(doom-darken blue 0.7)))
    :height 0.9)
   (mode-line-emphasis
    :foreground (if kev-doom-vibrant-brighter-modeline base8 highlight))


   (whitespace-empty :background bg)

   (whitespace-indentation :inherit 'default)
   (whitespace-big-indent :inherit 'default)

   ;; --- major-mode faces -------------------
   ;; css-mode / scss-mode
   (css-proprietary-property :foreground orange)
   (css-property             :foreground green)
   (css-selector             :foreground blue)

   ;; markdown-mode
   (markdown-header-face :inherit 'bold :foreground red)

   ;; org-mode
   (org-hide :foreground hidden)
   (solaire-org-hide-face :foreground hidden-alt)

;   (hl-fill-column-face :background bg-alt :foreground fg-alt)
   ;; sets the hover thing indirectly
   (lsp-face-highlight-textual :background dark-blue :inherit 'bold)
   ;; don't think these two do anything
   (lsp-ui-peek-highlight :foreground yellow :inherit 'bold)

   ;; various doom things are inherited from these.
   ;(diff-refine-added :inherit 'diff-added :background (doom-darken green 0.5))
   (magit-diff-added-highlight :inherit 'diff-added :background (doom-darken green 0.7))
   (magit-diff-added :inherit 'diff-added :background (doom-darken green 0.7))
   (smerge-lower :inherit 'diff-added)
   ;; (magit-diff-base :background "darkgreen")

   ;; stolen from doom-solarized-dark-high
   ;; emacs/.local/straight/repos/themes/themes/doom-solarized-dark-high-contrast-theme.el
   ;;
   ((font-lock-keyword-face &override)  :weight 'bold)
   ((font-lock-constant-face &override) :weight 'bold)
   ((font-lock-type-face &override)     :slant 'italic)
   ((font-lock-builtin-face &override)  :slant 'italic)

   ;;;; outline (affects org-mode)
   ((outline-1 &override) :foreground blue)
   ((outline-2 &override) :foreground (doom-darken green 0.1))
   ((outline-3 &override) :foreground teal)
   ((outline-4 &override) :foreground (doom-darken blue 0.2))
   ((outline-5 &override) :foreground (doom-darken green 0.2))
   ((outline-6 &override) :foreground (doom-darken teal 0.2))
   ((outline-7 &override) :foreground (doom-darken blue 0.4))
   ((outline-8 &override) :foreground (doom-darken green 0.4))
   ;;;; org <built-in>
   ((org-block &override) :background (doom-darken blue 0.8))
   ((org-block-begin-line &override) :foreground comments :background (doom-darken blue 0.8))
   ;;;; vterm
   (vterm-color-black   :background (doom-lighten base0 0.75)   :foreground base0)
   (vterm-color-red     :background (doom-lighten red 0.75)     :foreground red)
   (vterm-color-green   :background (doom-lighten green 0.75)   :foreground green)
   (vterm-color-yellow  :background (doom-lighten yellow 0.75)  :foreground yellow)
   (vterm-color-blue    :background (doom-lighten blue 0.75)    :foreground blue)
   (vterm-color-magenta :background (doom-lighten magenta 0.75) :foreground magenta)
   (vterm-color-cyan    :background (doom-lighten cyan 0.75)    :foreground cyan)
   (vterm-color-white   :background (doom-lighten base8 0.75)   :foreground base8)

   ;(default ((t (:background "black"))))
   ;(default :background bg)
   )


  ;; --- extra variables --------------------
  ;;
  ;; ()
   ;; taken from
   ;;;; lsp-mode and lsp-ui-mode
   ;; (lsp-ui-peek-highlight :foreground yellow)
   ;; (lsp-ui-sideline-symbol-info :foreground (doom-blend comments bg 0.85)
   ;;                              :background bg-alt)
   ;;
      ;;;; lsp-mode and lsp-ui-mode

  )

;;; doom-vibrant-theme.el ends here
