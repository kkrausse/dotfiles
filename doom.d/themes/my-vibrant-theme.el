;; doom-vibrant-theme.el --- a more vibrant version of doom-one -*- no-byte-compile: t; -*-
;; see https://github.com/doomemacs/themes/blob/master/themes/doom-one-theme.el
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
  ((bg         '("grey3"   "#080808" "black"))
   (bg-alt     '("grey15"  "#262626" "black")) ;; current line hightlighted & dired
   (base0      '("#1B2229" "black"   "black"        ))
   (base1      '("#1c1f24" "#1e1e1e" "brightblack"  ))
   (base2      '("#21272d" "#21212d" "brightblack"  ))
   (base3      '("#23272e" "#262626" "brightblack"  ))
   (base4      '("#484854" "#5e5e5e" "brightblack"  ))
   (base5      '("#62686E" "#666666" "brightblack"  ))
   (base6      '("#757B80" "#7b7b7b" "brightblack"  ))
   (base7      '("#9ca0a4" "#979797" "brightblack"  ))
   (base8      '("#DFDFDF" "#dfdfdf" "white"        ))
   (fg         '("grey70"  "#b2b2b2" "white"        ))
   (fg-alt     '("grey85"  "#d9d9d9" "brightwhite"  ))

   (grey       base4)
   (red        '("#ed5147" "#ff6655" "brightred"    ))
   (orange     '("#e69055" "#dd8844" "yellow"       ))
   (green      '("#3bd188" "#99bb66" "brightgreen"  ))
   (teal       '("#4db5bd" "#44b9b1" "cyan"         ))
   (yellow     '("#FCCE7B" "#ffd7af" "brightyellow" ))
   (blue       '("#7A7AFF" "#8787ff" "brightblue"   ))
   (dark-blue  '("#1f5582" "#005f87" "blue"         ))
   (magenta    '("#db7b9e" "#d787af" "brightmagenta"))
   ;; was #d481d0, which sat 0.023 from `teal' under deuteranopia/protanopia --
   ;; i.e. identical to a red-green eye. This is 0.080 away and higher contrast.
   (violet     '("#e0a3ff" "#d7afff" "magenta"      )) ;a9a1e1, #d481d0
   (cyan       '("#5cEfFF" "#5fffff" "brightcyan"   ))
   (dark-cyan  '("#6A8FBF" "#5f87af" "blue"         ))

   ;; Diff backgrounds. A conventional dark-green/dark-red pair measures 0.046
   ;; apart under red-green simulation -- effectively the same color. This pair
   ;; still reads green/red to normal vision but separates on lightness (0.125),
   ;; which is an axis red-green deficiency leaves intact. Measured sep: 0.108.
   (diff-added-bg   '("#082800" "#002200" "black"      ))
   (diff-removed-bg '("#503838" "#585858" "brightblack"))

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
   (keywords       orange)
   (functions      blue)
   (methods        cyan)
   (operators      blue) ;; was blue
   (type           (doom-darken yellow 0.1))
   (strings        (doom-darken green 0.1))
   (variables      teal)
   (constants      violet)
   (numbers        violet)
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

  ;; base theme face overrides
  (((all-the-icons-dblue &override) :foreground dark-cyan)
   (centaur-tabs-unselected :background bg-alt :foreground base6)
   (elscreen-tab-other-screen-face :background "#353a42" :foreground "#1e2022")

   ;; lisp
   (highlight-quoted-symbol :foreground (doom-darken yellow 0.15))

   ;;;;;;;; Editor ;;;;;;;;
   (cursor :background fg-alt)
   (hl-line :background (doom-darken orange 0.8))

   ;;;;;;;; Brackets ;;;;;;;;
   ;; Rainbow-delimiters

   ;; 4-colour cycle rather than 3: adding blue widens the spread on the
   ;; blue<->yellow axis, which is the axis that survives red-green deficiency.
   ;; Depths 3/4 used to be defined twice; the duplicates are gone.
   (rainbow-delimiters-depth-1-face :foreground (doom-lighten red 0.5))
   (rainbow-delimiters-depth-2-face :foreground yellow)
   (rainbow-delimiters-depth-3-face :foreground (doom-lighten cyan 0.2))
   (rainbow-delimiters-depth-4-face :foreground blue)
   (rainbow-delimiters-depth-5-face :foreground (doom-lighten red 0.5))
   (rainbow-delimiters-depth-6-face :foreground yellow)
   (rainbow-delimiters-depth-7-face :foreground (doom-lighten cyan 0.2))
   (rainbow-delimiters-depth-8-face :foreground blue)
   (rainbow-delimiters-depth-9-face :foreground (doom-lighten red 0.5))
   ;; unmatched/mismatched must not rely on hue alone
   (rainbow-delimiters-unmatched-face  :foreground red :weight 'bold :underline t)
   (rainbow-delimiters-mismatched-face :foreground red :weight 'bold :underline t)
   ;; Bracket pairing
   ((show-paren-match &override) :foreground nil :background base5 :bold t)
   ;; was the raw X11 "red", not the theme's red; also gains a weight cue so the
   ;; mismatch reads as different from `show-paren-match' without relying on hue
   ((show-paren-mismatch &override) :foreground bg :background red :weight 'bold)

   ((clojure-keyword-face &override) :foreground magenta :bold nil)
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
   ;; (dark text on the solid match background -- that part was right). Slots 2
   ;; and 3 were green/yellow, which measure 0.051 apart under red-green
   ;; simulation; cyan/orange spread the four slots to a 0.112 worst pair.
   ((orderless-match-face-0 &override) :foreground base1 :background blue)
   ((orderless-match-face-1 &override) :foreground base1 :background magenta)
   ((orderless-match-face-2 &override) :foreground base1 :background cyan)
   ((orderless-match-face-3 &override) :foreground base1 :background orange)
   ;; was defined three times; the first two were identical and dead
   ((custom-modified &override) :foreground red :background (doom-blend blue bg 0.5))
   ;; these two were both :background red, so they marked the same thing twice.
   ;; common-part is the prefix you already typed; first-difference is where the
   ;; candidates diverge -- that one gets the attention-grabbing treatment.
   ((completions-common-part &override)
    :foreground fg-alt :background dark-blue :weight 'normal)
   ((completions-first-difference &override)
    :foreground fg-alt :background red :weight 'bold :underline t)
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
   ;;
   ;; Added/removed is the most consequential distinction in the editor, and it
   ;; was previously carried by hue alone -- with only the added side actually
   ;; overridden, so the two were never balanced against each other. Removed now
   ;; also carries italic, so the cue survives even if the colours don't.
   (diff-added                     :background diff-added-bg)
   (diff-removed                   :background diff-removed-bg :slant 'italic)
   (diff-refine-added              :background (doom-lighten diff-added-bg 0.20) :weight 'bold)
   (diff-refine-removed            :background (doom-lighten diff-removed-bg 0.20) :weight 'bold :slant 'italic)
   (magit-diff-added               :inherit 'diff-added)
   (magit-diff-added-highlight     :background (doom-lighten diff-added-bg 0.12) :foreground fg-alt)
   (magit-diff-removed             :inherit 'diff-removed)
   ;; fg-alt rather than fg: default fg on this lighter background is only
   ;; 3.5:1, below AA. fg-alt brings it to 5.3:1 without giving up separation.
   (magit-diff-removed-highlight   :background (doom-lighten diff-removed-bg 0.12) :foreground fg-alt :slant 'italic)
   (smerge-lower                   :inherit 'diff-added)
   (smerge-upper                   :inherit 'diff-removed)
   (smerge-refined-added           :inherit 'diff-refine-added)
   (smerge-refined-removed         :inherit 'diff-refine-removed)
   ;; (magit-diff-base :background "darkgreen")

   ;; ediff is entirely hue-coded out of the box; reuse the measured pair
   (ediff-current-diff-A        :background diff-removed-bg :slant 'italic)
   (ediff-current-diff-B        :background diff-added-bg)
   (ediff-current-diff-C        :background (doom-blend blue bg 0.25))
   (ediff-fine-diff-A           :background (doom-lighten diff-removed-bg 0.20) :weight 'bold :slant 'italic)
   (ediff-fine-diff-B           :background (doom-lighten diff-added-bg 0.20) :weight 'bold)
   (ediff-fine-diff-C           :background (doom-blend blue bg 0.40) :weight 'bold)
   (ediff-even-diff-A           :background bg-alt :slant 'italic)
   (ediff-even-diff-B           :background bg-alt)
   (ediff-odd-diff-A            :background base3 :slant 'italic)
   (ediff-odd-diff-B            :background base3)

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
   ;; bright slots were unset, so bright ANSI output fell through to vterm's
   ;; own defaults and ignored this palette entirely
   (vterm-color-bright-black   :background (doom-lighten base5 0.75)              :foreground base5)
   (vterm-color-bright-red     :background (doom-lighten (doom-lighten red 0.3) 0.75)     :foreground (doom-lighten red 0.3))
   (vterm-color-bright-green   :background (doom-lighten (doom-lighten green 0.3) 0.75)   :foreground (doom-lighten green 0.3))
   (vterm-color-bright-yellow  :background (doom-lighten (doom-lighten yellow 0.3) 0.75)  :foreground (doom-lighten yellow 0.3))
   (vterm-color-bright-blue    :background (doom-lighten (doom-lighten blue 0.3) 0.75)    :foreground (doom-lighten blue 0.3))
   (vterm-color-bright-magenta :background (doom-lighten (doom-lighten magenta 0.3) 0.75) :foreground (doom-lighten magenta 0.3))
   (vterm-color-bright-cyan    :background (doom-lighten (doom-lighten cyan 0.3) 0.75)    :foreground (doom-lighten cyan 0.3))
   (vterm-color-bright-white   :background (doom-lighten fg-alt 0.75)             :foreground fg-alt)

   ;;;; numbers -- font-lock-number-face is a distinct face in Emacs 29+, and it
   ;;;; was NOT picking up the bold that `font-lock-constant-face' gets below.
   ;;;; violet numbers against teal variables measured 0.023 apart under
   ;;;; red-green simulation, which is indistinguishable; they sit adjacent
   ;;;; constantly (`x = 42'). Weight is the cue that survives regardless.
   ((font-lock-number-face &override) :weight 'bold)

   ;;;; flycheck -- differentiate by underline STYLE, not only colour
   (flycheck-error   :underline `(:style wave :color ,red))
   (flycheck-warning :underline `(:style wave :color ,yellow) :weight 'bold)
   (flycheck-info    :underline `(:style line :color ,cyan))
   (flycheck-fringe-error   :foreground red     :weight 'bold)
   (flycheck-fringe-warning :foreground yellow  :weight 'bold)
   (flycheck-fringe-info    :foreground cyan)

   ;;;; hl-todo
   (hl-todo :weight 'bold :slant 'italic)

   ;;;; org keywords -- done is distinguished by lightness + weight rather than
   ;;;; the usual red/green pair
   ((org-todo &override) :foreground orange :weight 'bold)
   ((org-done &override) :foreground comments :weight 'normal)
   )
  ;; base theme variable overrides
  ())

;;; doom-vibrant-theme.el ends here
