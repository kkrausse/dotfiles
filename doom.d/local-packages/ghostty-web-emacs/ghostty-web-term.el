;;; ghostty-web-term.el --- Ghostty terminal in an Emacs xwidget -*- lexical-binding: t; -*-

;; Author: Kevin Krausse
;; Keywords: terminals, processes
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Runs a real shell inside an Emacs WebKit xwidget buffer, rendered by
;; ghostty-web (Ghostty's VT parser compiled to WASM).  A small Node server
;; provides the PTY over a loopback WebSocket; this file starts one such server
;; per terminal buffer and points that buffer's xwidget at it.
;;
;; Usage:
;;
;;   M-x ghostty-web-term
;;
;; How input works, because it is not obvious and constrains everything here:
;;
;; Emacs cannot synthesize key events into a WebKit xwidget on macOS.  The only
;; API for that, `xwidget-perform-lispy-event', has its entire body inside
;; `#ifdef USE_GTK' in src/xwidget.c, so on a --with-ns build it is a no-op and
;; `xwidget-webkit-edit-mode' does nothing.
;;
;; Instead, the NS port routes keys natively: src/nsxwidget.m evaluates
;; `xwHasFocus()' on every keyDown and hands the raw event to WebKit when
;; `document.activeElement' is an INPUT or TEXTAREA, otherwise forwarding it to
;; Emacs.  The page therefore keeps ghostty-web's helper textarea focused, which
;; gives the terminal the full keyboard -- modifiers, ESC, C-c and all -- with no
;; round trip through Emacs.
;;
;; The consequence is a modal keyboard.  While the terminal holds focus, Emacs
;; bindings in this buffer do not fire.  Press a handoff chord (`C-w' by default,
;; see `ghostty-web-term-handoff-chords') to get the keyboard back.
;;
;; That handoff must be a real first-responder transfer.  Blurring the textarea
;; is not enough: the WKWebView stays first responder and relays every keystroke
;; to Emacs from inside an asynchronous `evaluateJavaScript' completion handler,
;; which mostly works for single keys and reliably breaks prefix sequences like
;; `C-w h', `C-x o' and ESC-as-meta.  Only `makeFirstResponder:emacswindow'
;; genuinely transfers the keyboard, and the sole way to trigger it from a page is
;; to post "C-g" to the script message handler Emacs registers (see the C-g branch
;; of `userContentController:didReceiveScriptMessage:' in src/nsxwidget.m), which
;; gives up focus without relaying anything to the shell.
;;
;; Returning to the terminal needs a mouse click.  `nsxwidget.m' contains exactly
;; two `makeFirstResponder' calls and both hand off *to* Emacs; nothing gives an
;; xwidget the keyboard back except WKWebView's default `mouseDown:' handling.
;; So selecting the terminal's window cannot also give it the keyboard, and a
;; command to do so is not merely missing -- it is not expressible.  Synthesizing
;; the click does not help either: a CGEvent left-click at the widget was measured
;; to leave Emacs as first responder, because `mouseDown:' forwards to
;; `[emacswindow mouseDown:]' before calling `[super mouseDown:]'.
;;
;; Emacs-to-shell communication goes through `xwidget-webkit-execute-script'
;; against the page's `window.gw' object.
;;
;; Paste is the other thing that looks like it should be simple and is not.  WebKit
;; will not let the page read the clipboard here: `navigator.clipboard.readText'
;; rejects with NotAllowedError, and `document.execCommand("paste")' only
;; "succeeds" by making WebKit show a native Paste bubble that has to be clicked
;; for every paste.  Emacs can read the clipboard for free, so Cmd-V in the page is
;; turned into a paste *request*: the page sends it over the control channel Emacs
;; hosts (or, if that socket is down, over the PTY WebSocket to be relayed on the
;; server's stdout), and Emacs answers with the clipboard as it is right then.
;; Nothing is cached on the page, deliberately -- a dictation or clipboard-manager
;; tool that copies and immediately presses Cmd-V would outrun any cache.  Whether
;; to wrap a paste in bracketed-paste markers is decided in the page, the only side
;; that knows the terminal's DECSET 2004 state.

;;; Code:

(require 'xwidget)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'url-util)
(require 'cl-lib)

(defgroup ghostty-web-term nil
  "Ghostty terminal inside an Emacs xwidget."
  :group 'terminals
  :prefix "ghostty-web-term-")

(defcustom ghostty-web-term-directory
  (expand-file-name
   "server"
   (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Directory containing the PTY server (server.js and node_modules)."
  :type 'directory)

(defcustom ghostty-web-term-node-program "node"
  "Node executable used to run the PTY server."
  :type 'string)

(defcustom ghostty-web-term-port 0
  "Port for the PTY server.  0 lets the OS choose a free port."
  :type 'integer)

(defcustom ghostty-web-term-command nil
  "Shell command string run in the PTY, or nil for an interactive login shell.
Set this to attach a multiplexer, e.g. \"tmux new-session -A -s emacs\"."
  :type '(choice (const :tag "Interactive login shell" nil) string))

(defcustom ghostty-web-term-directory-for-shell nil
  "Working directory for the shell.  nil means the user's home directory."
  :type '(choice (const :tag "Home" nil) directory))

(defcustom ghostty-web-term-font-size 13
  "Terminal font size in pixels."
  :type 'integer)

(defcustom ghostty-web-term-handoff-chords "ctrl-w,ctrl-Escape"
  "Chords, comma separated, that hand the keyboard back to Emacs.
Each is modifiers joined by \"-\" followed by a KeyboardEvent key name,
e.g. \"ctrl-w\" or \"ctrl-Escape\".

These are swallowed by the page, so the shell never sees them -- notably
`ctrl-w' will not word-erase on its way out.  The handoff is a real
first-responder transfer, so afterwards Emacs behaves completely normally
(prefix keys, ESC, window commands).  Returning to the terminal requires a
mouse click: Emacs offers no way to give an xwidget back the keyboard."
  :type 'string)

(defcustom ghostty-web-term-alt-screen-wheel "arrows"
  "Wheel behavior while a full-screen app (less, vim, htop) is running.

On the alternate screen there is no scrollback to scroll, so terminals
translate the wheel into arrow keys.  \"arrows\" does that, accumulating
fractional lines so macOS trackpad momentum cannot spray keypresses;
\"off\" ignores the wheel entirely; \"default\" restores ghostty-web's own
translation, which emits up to 5 arrows per wheel event.

On the normal screen the wheel always scrolls the scrollback instead."
  :type '(choice (const "arrows") (const "off") (const "default")))

(defcustom ghostty-web-term-wheel-sensitivity 1.0
  "Multiplier for wheel-to-arrow-key conversion on the alternate screen."
  :type 'number)

(defcustom ghostty-web-term-startup-timeout 15
  "Seconds to wait for the PTY server to report readiness."
  :type 'number)

;;; Server lifecycle
;;
;; One server process per terminal buffer.
;;
;; A singleton would work -- the Node side spawns a PTY per WebSocket connection,
;; so a single process genuinely serves N terminals -- but only for as long as its
;; lifetime is tracked by hand.  Nothing owned that process, so it had to be
;; reference-counted against the set of live terminal buffers, and that bookkeeping
;; is exactly the kind that rots: the hook meant to stop the server when the last
;; terminal died could not apply to terminals that were already open, because the
;; mode body had already run in them.  Tying the process to the buffer makes
;; lifetime correct by construction instead: `kill-buffer' takes the server with
;; it, and there is no shared state left to get out of step.
;;
;; The cost is a node process (~40-60MB) and a startup handshake (~1s) per
;; terminal, where a warm shared server opened them instantly.  That is a fine
;; trade at the handful of terminals anyone keeps open, and it buys back the
;; blast radius too: restarting or losing one server no longer touches the others.

(defvar-local ghostty-web-term--client-id nil
  "Identifier this buffer's page uses when talking to Emacs.
Also names this buffer's server process and its log buffer.")

(defvar ghostty-web-term--client-counter 0
  "Counter handing out `ghostty-web-term--client-id' values.")

(defun ghostty-web-term--next-client-id ()
  "Return a fresh client id."
  (number-to-string (cl-incf ghostty-web-term--client-counter)))

(cl-defstruct (ghostty-web-term--server
               (:constructor ghostty-web-term--server-make)
               (:copier nil))
  "One terminal's PTY server."
  ;; The node process.
  process
  ;; Plist of :url, :port and :token, filled in from the readiness handshake.
  info
  ;; Trailing partial line of stdout, held until the rest of it arrives.
  (stdout ""))

(defvar-local ghostty-web-term--server nil
  "This buffer's `ghostty-web-term--server', or nil.")

(defconst ghostty-web-term--ready-prefix "GHOSTTY_WEB_READY "
  "Prefix of the handshake line the server prints once listening.")

(defconst ghostty-web-term--paste-prefix "GHOSTTY_WEB_PASTE_REQUEST "
  "Prefix of the line the server prints when a page asks Emacs to paste.")

(defun ghostty-web-term--server-live-p (&optional server)
  "Return non-nil when SERVER, or this buffer's server, is running."
  (let ((server (or server ghostty-web-term--server)))
    (and (ghostty-web-term--server-p server)
         (process-live-p (ghostty-web-term--server-process server)))))

(defun ghostty-web-term--info ()
  "Return this buffer's server info plist (:url, :port, :token), or nil."
  (and (ghostty-web-term--server-p ghostty-web-term--server)
       (ghostty-web-term--server-info ghostty-web-term--server)))

(defun ghostty-web-term--log-buffer-name (client)
  "Return the name of the log buffer for the server serving CLIENT.
One log buffer per server: several node processes writing into a single
buffer interleave into something not worth reading."
  (format "*ghostty-web-server-%s*" client))

(defun ghostty-web-term--filter (proc string)
  "Handle STRING from server PROC one complete line at a time.
Also echoes into the process buffer, so the server's log buffer actually
shows its diagnostics -- setting a filter otherwise suppresses them, which
made the \"see the server buffer\" advice useless."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (save-excursion (goto-char (point-max)) (insert string))))))
  ;; The state lives on the process, not in a global and not in whatever buffer
  ;; happens to be current: output arrives long after the call that started this
  ;; server returned.
  (let ((server (process-get proc 'gw-server)))
    (when (ghostty-web-term--server-p server)
      ;; Split the whole chunk before acting on any of it.  Only a partial tail is
      ;; kept, so the accumulator cannot grow without bound, and the accumulator is
      ;; never left mid-update while `--handle-line' runs arbitrary code (it can
      ;; answer a paste request), which is how a line would get handled twice.
      (let ((acc (concat (ghostty-web-term--server-stdout server) string))
            (lines nil))
        (while (string-match "\\`\\([^\n]*\\)\n" acc)
          (push (match-string 1 acc) lines)
          (setq acc (substring acc (match-end 0))))
        (setf (ghostty-web-term--server-stdout server) acc)
        (dolist (line (nreverse lines))
          (ghostty-web-term--handle-line proc server line))))))

(defun ghostty-web-term--handle-line (proc server line)
  "Act on one complete output LINE from SERVER, whose process is PROC."
  (cond
   ((and (not (ghostty-web-term--server-info server))
         (string-prefix-p ghostty-web-term--ready-prefix line))
    (let* ((payload (substring line (length ghostty-web-term--ready-prefix)))
           (parsed (condition-case err
                       (json-parse-string payload :object-type 'plist)
                     (error
                      (message "ghostty-web-term: bad handshake: %S" err)
                      nil))))
      (when parsed
        (setf (ghostty-web-term--server-info server)
              (list :url (plist-get parsed :url)
                    :port (plist-get parsed :port)
                    :token (plist-get parsed :token))))))
   ((string-prefix-p ghostty-web-term--paste-prefix line)
    ;; The page's fallback paste path, for when its control socket is down.  This
    ;; server serves exactly one terminal, so the process knows which buffer
    ;; asked and the client id in the payload is only a cross-check.
    (let* ((payload (substring line (length ghostty-web-term--paste-prefix)))
           (parsed (ignore-errors
                     (json-parse-string payload :object-type 'plist)))
           (client (and parsed (plist-get parsed :client))))
      (ghostty-web-term--serve-paste-request client (process-get proc 'gw-buffer))))))

(defun ghostty-web-term--check-installed ()
  "Signal a user error unless the server and its dependencies are present."
  (unless (file-directory-p ghostty-web-term-directory)
    (user-error "ghostty-web-term: no server directory at %s"
                ghostty-web-term-directory))
  (unless (file-exists-p (expand-file-name "server.js" ghostty-web-term-directory))
    (user-error "ghostty-web-term: server.js missing in %s"
                ghostty-web-term-directory))
  (unless (file-directory-p (expand-file-name "node_modules" ghostty-web-term-directory))
    (user-error "ghostty-web-term: dependencies not installed.  Run: cd %s && npm install"
                ghostty-web-term-directory))
  (unless (executable-find ghostty-web-term-node-program)
    (user-error "ghostty-web-term: %s not found in exec-path"
                ghostty-web-term-node-program)))

(defun ghostty-web-term--server-start (client)
  "Start a PTY server for CLIENT and return its `ghostty-web-term--server'.
Blocks until the server reports readiness, so the caller gets a URL that is
actually loadable, and signals -- taking the process with it rather than
leaving an orphan node behind -- if readiness never comes."
  (ghostty-web-term--check-installed)
  (let* ((default-directory ghostty-web-term-directory)
         (log (ghostty-web-term--log-buffer-name client))
         (server (ghostty-web-term--server-make))
         (args (append
                (list "server.js" "--port" (number-to-string ghostty-web-term-port))
                (when ghostty-web-term-command
                  (list "--cmd" ghostty-web-term-command))
                (when ghostty-web-term-directory-for-shell
                  (list "--cwd" (expand-file-name
                                 ghostty-web-term-directory-for-shell)))))
         (proc (make-process
                :name (format "ghostty-web-server-%s" client)
                ;; Deliberately not the terminal's own buffer: that is an xwidget
                ;; buffer, and the server's diagnostics would be inserted into it.
                :buffer (get-buffer-create log)
                :command (cons ghostty-web-term-node-program args)
                :connection-type 'pipe
                :noquery t
                :filter #'ghostty-web-term--filter
                :sentinel #'ghostty-web-term--sentinel)))
    (setf (ghostty-web-term--server-process server) proc)
    (process-put proc 'gw-server server)
    ;; Block briefly for the handshake so callers get a usable URL.
    (let ((deadline (+ (float-time) ghostty-web-term-startup-timeout)))
      (while (and (not (ghostty-web-term--server-info server))
                  (process-live-p proc)
                  (< (float-time) deadline))
        (accept-process-output proc 0.05)))
    (unless (ghostty-web-term--server-info server)
      (let ((msg (if (process-live-p proc)
                     "timed out waiting for server handshake"
                   "server exited during startup")))
        (ghostty-web-term--server-kill server)
        (user-error "ghostty-web-term: %s (see %s)" msg log)))
    server))

(defun ghostty-web-term--server-kill (server)
  "Delete SERVER's process, killing the shell it hosts.  Harmless if already dead."
  (when (ghostty-web-term--server-p server)
    (let ((proc (ghostty-web-term--server-process server)))
      (when (process-live-p proc)
        ;; Marked so the sentinel does not report a deliberate stop as a crash.
        (process-put proc 'gw-stopping t)
        (delete-process proc)))
    (setf (ghostty-web-term--server-info server) nil)))

(defun ghostty-web-term--server-adopt (server buffer)
  "Make SERVER BUFFER's server, and BUFFER the terminal SERVER serves."
  (process-put (ghostty-web-term--server-process server) 'gw-buffer buffer)
  (with-current-buffer buffer
    (setq ghostty-web-term--server server)))

(defun ghostty-web-term--sentinel (proc event)
  "Note that server PROC ended.  EVENT is the status change."
  (unless (string-match-p "\\`\\(run\\|open\\)" event)
    (let ((server (process-get proc 'gw-server))
          (buf (process-get proc 'gw-buffer)))
      (when (ghostty-web-term--server-p server)
        (setf (ghostty-web-term--server-info server) nil))
      ;; A server dying by itself takes its shell with it and leaves the page
      ;; retrying against a dead port, so say so.  Nothing to announce for a
      ;; server we stopped on purpose, nor for one that never got as far as
      ;; belonging to a buffer -- `--server-start' signals about that one itself,
      ;; and this would only get in front of that message.
      (when (and (not (process-get proc 'gw-stopping))
                 (buffer-live-p buf))
        (message "ghostty-web-term: server for %s exited (%s)"
                 (buffer-name buf) (string-trim event))))))

(defun ghostty-web-term--assert-terminal ()
  "Signal unless the current buffer is a ghostty-web terminal."
  (unless (memq (current-buffer) (ghostty-web-term--buffers))
    (user-error "ghostty-web-term: %s is not a ghostty-web terminal"
                (buffer-name))))

(defun ghostty-web-term--start-and-load ()
  "Give the current terminal a fresh server and point its page at it.
Return the new server's info plist.

Loading the page is not optional: the server's port and token are carried in
the URL, so a new server is only reachable through a new URL.  Which is also
why this makes no attempt to keep the shell -- that shell died with the
server it was running under."
  (let ((xw (or (ghostty-web-term--buffer-xwidget (current-buffer))
                (user-error "ghostty-web-term: no xwidget in %s" (buffer-name))))
        (client (or ghostty-web-term--client-id
                    (setq ghostty-web-term--client-id
                          (ghostty-web-term--next-client-id)))))
    (let ((server (ghostty-web-term--server-start client)))
      (ghostty-web-term--server-adopt server (current-buffer))
      (xwidget-webkit-goto-uri xw (ghostty-web-term--url client server))
      (ghostty-web-term--server-info server))))

(defun ghostty-web-term-start-server ()
  "Start this terminal's PTY server unless it is already running.
Return its info plist.

Worth running only after a server has died, and it costs that terminal's
shell: see `ghostty-web-term-restart-server'.  Other terminals are not
touched -- each one has its own server."
  (interactive)
  (ghostty-web-term--assert-terminal)
  (if (ghostty-web-term--server-live-p)
      (let ((info (ghostty-web-term--info)))
        (message "ghostty-web-term: server for %s already running on port %s"
                 (buffer-name) (plist-get info :port))
        info)
    (let ((info (ghostty-web-term--start-and-load)))
      (message "ghostty-web-term: server for %s started on port %s"
               (buffer-name) (plist-get info :port))
      info)))

(defun ghostty-web-term-stop-server ()
  "Stop this terminal's PTY server, killing its shell.
Other terminals keep running: each has a server of its own."
  (interactive)
  (ghostty-web-term--assert-terminal)
  (if (not (ghostty-web-term--server-live-p))
      (message "ghostty-web-term: no server running for %s" (buffer-name))
    (ghostty-web-term--server-kill ghostty-web-term--server)
    (message "ghostty-web-term: server for %s stopped" (buffer-name))))

(defun ghostty-web-term-restart-server ()
  "Restart this terminal's PTY server and reload its page.

This kills the shell, unavoidably: the new server listens on a new port with
a new token, so the page has to be navigated to a new URL, and navigating an
xwidget destroys the PTY behind it anyway.  Point
`ghostty-web-term-command' at a multiplexer for a session that survives it.

Only this terminal is affected."
  (interactive)
  (ghostty-web-term--assert-terminal)
  (when (y-or-n-p (format "Restart the server for %s (kills its shell)? "
                          (buffer-name)))
    (ghostty-web-term--server-kill ghostty-web-term--server)
    (let ((info (ghostty-web-term--start-and-load)))
      (message "ghostty-web-term: server for %s restarted on port %s"
               (buffer-name) (plist-get info :port)))))

;;; Keyboard ownership: the focus module
;;
;; Emacs cannot give an xwidget the keyboard.  Not "there is no command for it" --
;; it is not expressible.  Checked against Emacs 30.2: `src/nsxwidget.h' exports
;; 18 `nsxwidget_*' functions and none touch responders; the two
;; `makeFirstResponder:' calls in `nsxwidget.m' both hand focus TO Emacs (isearch,
;; and the "C-g" script-message branch); and `xwidget-perform-lispy-event' is
;; entirely inside `#ifdef USE_GTK', which is why `xwidget-webkit-edit-mode' does
;; nothing here.  The only thing that gives a WKWebView first responder is
;; WKWebView's own `mouseDown:'.  Hence "Emacs has the keyboard -- click to type".
;;
;; module/gw-focus.m closes that gap with the one AppKit call the port never
;; makes.  A dynamic module runs in Emacs's process on Emacs's main thread, so it
;; can ask the window to make the XwWebView first responder directly.  No
;; synthesized clicks, no Accessibility, no private API: it lands in exactly the
;; state a real click lands in, and the page can still hand the keyboard back by
;; posting "C-g" the way it always could.
;;
;; Everything here fails soft.  With no module -- not built, not loadable, not
;; macOS -- the terminal behaves exactly as it did before: the page's textarea
;; gets DOM focus and a click is still needed.

;; Provided by module/gw-focus.dylib once loaded; every call site checks
;; `fboundp' first, since the module is optional by design.
(declare-function gw-focus-take "gw-focus" (&optional match))
(declare-function gw-focus-release "gw-focus" ())
(declare-function gw-focus-state "gw-focus" ())
(declare-function gw-focus-count "gw-focus" ())

(defcustom ghostty-web-term-focus-module
  (expand-file-name
   "module/gw-focus.dylib"
   (file-name-directory (or load-file-name buffer-file-name default-directory)))
  "Path to the compiled focus module, or nil to never use one.
Built from `module/gw-focus.m' in this package."
  :type '(choice (const :tag "Do not use a focus module" nil) file))

(defcustom ghostty-web-term-focus-module-auto-build t
  "Compile the focus module on demand when it is missing.
The build is one `clang' invocation and takes well under a second.  A
failure is reported once and never retried in this session."
  :type 'boolean)

(defcustom ghostty-web-term-focus-module-include-dir nil
  "Directory holding `emacs-module.h', or nil to derive it from this Emacs."
  :type '(choice (const :tag "Derive from `data-directory'" nil) directory))

(defvar ghostty-web-term--focus-module-state nil
  "Cached outcome of loading the focus module: nil untried, t loaded, `failed'.
Kept so a failure is not retried -- and re-reported -- on every window
switch once `ghostty-web-term-autofocus-mode' is on.")

(defun ghostty-web-term--focus-module-include-dir ()
  "Return the directory that should hold `emacs-module.h'.
Derived from `data-directory', which lands on the install prefix for a
Homebrew, /usr/local or self-built Emacs alike."
  (or ghostty-web-term-focus-module-include-dir
      (expand-file-name "include" (expand-file-name "../../../.." data-directory))))

(defun ghostty-web-term-build-focus-module ()
  "Compile the focus module from `module/gw-focus.m'.
Signals with the compiler output when the build fails."
  (interactive)
  (unless ghostty-web-term-focus-module
    (user-error "ghostty-web-term: `ghostty-web-term-focus-module' is nil"))
  (let* ((dylib (expand-file-name ghostty-web-term-focus-module))
         (source (expand-file-name "gw-focus.m" (file-name-directory dylib)))
         (include (ghostty-web-term--focus-module-include-dir))
         (header (expand-file-name "emacs-module.h" include))
         (buf (get-buffer-create "*ghostty-web-focus-build*")))
    (unless (file-exists-p source)
      (user-error "ghostty-web-term: focus module source missing at %s" source))
    (unless (file-exists-p header)
      (user-error "ghostty-web-term: emacs-module.h not found in %s (set %s)"
                  include "ghostty-web-term-focus-module-include-dir"))
    (with-current-buffer buf
      (let ((inhibit-read-only t)) (erase-buffer)))
    (let ((status (apply #'call-process "clang" nil buf t
                         (list "-bundle" "-fobjc-arc" "-O2" "-Wall"
                               "-framework" "AppKit" "-framework" "WebKit"
                               "-I" include "-o" dylib source))))
      (unless (eq status 0)
        (user-error "ghostty-web-term: focus module build failed (see %s)"
                    (buffer-name buf)))
      (message "ghostty-web-term: built %s" dylib)
      dylib)))

(defun ghostty-web-term--focus-module-ensure ()
  "Make the focus module available if it can be.  Return non-nil on success.

Never signals: this runs from a window hook, where an error would make
switching windows fail rather than merely leave the keyboard behind."
  (cond
   ((featurep 'gw-focus) t)
   ((eq ghostty-web-term--focus-module-state 'failed) nil)
   ((null ghostty-web-term-focus-module) nil)
   ;; `module-file-suffix' is the documented way to ask whether this Emacs can
   ;; load modules at all -- nil when it cannot.  Not `(featurep
   ;; \\='dynamic-modules)': that is absent from `features' in a plain Emacs even
   ;; when module loading works perfectly, so gating on it disabled this feature
   ;; entirely (measured -- it is present under Doom and missing under `emacs -Q',
   ;; same binary).
   ((not (and (eq window-system 'ns)
              module-file-suffix
              (fboundp 'module-load)))
    (setq ghostty-web-term--focus-module-state 'failed)
    nil)
   (t
    (let ((dylib (expand-file-name ghostty-web-term-focus-module)))
      (condition-case err
          (progn
            (when (and (not (file-exists-p dylib))
                       ghostty-web-term-focus-module-auto-build)
              (ghostty-web-term-build-focus-module))
            (if (not (file-exists-p dylib))
                (progn
                  (setq ghostty-web-term--focus-module-state 'failed)
                  (message "ghostty-web-term: no focus module at %s (M-x %s)"
                           dylib "ghostty-web-term-build-focus-module")
                  nil)
              (module-load dylib)
              (setq ghostty-web-term--focus-module-state
                    (if (featurep 'gw-focus) t 'failed))
              (eq ghostty-web-term--focus-module-state t)))
        (error
         (setq ghostty-web-term--focus-module-state 'failed)
         (message "ghostty-web-term: focus module unavailable: %s"
                  (error-message-string err))
         nil))))))

(defun ghostty-web-term--client-url-match (&optional buffer)
  "Return a URL fragment identifying BUFFER's page, or nil.
The trailing \"&\" matters: without it \"client=1\" also matches client 10.
`ghostty-web-term--url' always puts another parameter after the client id, so
the separator is always there."
  (let ((client (buffer-local-value 'ghostty-web-term--client-id
                                    (or buffer (current-buffer)))))
    (and client (format "client=%s&" client))))

(defun ghostty-web-term--take-keyboard (&optional buffer)
  "Give BUFFER's terminal the keyboard for real.  Return non-nil on success.
Does nothing without the focus module, which is the difference between
selecting the terminal's window and being able to type in it."
  (and (ghostty-web-term--focus-module-ensure)
       (fboundp 'gw-focus-take)
       (let ((match (ghostty-web-term--client-url-match buffer)))
         ;; With no client id, fall back to the module's own single-web-view
         ;; rule rather than grabbing the keyboard for some other page.
         (and (gw-focus-take match) t))))

(defun ghostty-web-term-release-keyboard ()
  "Hand the keyboard back to Emacs from Emacs's side.
`ghostty-web-term-blur' is the usual way and works by asking the page to post
\"C-g\"; this is for when the page cannot, having never had the keyboard or
having stopped responding."
  (interactive)
  (if (and (ghostty-web-term--focus-module-ensure) (fboundp 'gw-focus-release)
           (gw-focus-release))
      (message "ghostty-web-term: Emacs has the keyboard")
    (message "ghostty-web-term: could not move the keyboard (no focus module)")))

(defun ghostty-web-term-focus-state ()
  "Report which view currently owns the keyboard.
Useful when typing goes somewhere unexpected: it names the window's first
responder, which is the half of focus that no Lisp can see."
  (interactive)
  (if (and (ghostty-web-term--focus-module-ensure) (fboundp 'gw-focus-state))
      (message "ghostty-web-term: %s" (gw-focus-state))
    (message "ghostty-web-term: no focus module; %s"
             "cannot see first-responder state")))

;;;; Following window selection

(defun ghostty-web-term--autofocus-eligible-p ()
  "Return the terminal buffer that should take the keyboard now, or nil."
  (let ((buf (window-buffer (selected-window))))
    (and (buffer-local-value 'ghostty-web-term-mode buf)
         ;; Never steal the keyboard out from under a prompt: a minibuffer read
         ;; is the one place where losing keys silently is worst.
         (not (active-minibuffer-window))
         (not executing-kbd-macro)
         ;; No guard against a half-typed prefix sequence, deliberately.  There
         ;; is nothing to guard: this only runs when the *selected window
         ;; changed*, and a window changes selection as the result of a command
         ;; that has already finished, so no key sequence can straddle it.  An
         ;; earlier version tested `this-single-command-keys' and was worse than
         ;; useless -- that still holds the finished command's own keys when the
         ;; idle timer fires, so `C-x o' into the terminal looked like a pending
         ;; prefix and the keyboard never followed at all.
         (not (buffer-local-value 'isearch-mode buf))
         buf)))

(defun ghostty-web-term--autofocus-run (buffer)
  "Give BUFFER the keyboard if it is still the selected window's buffer."
  (when (and (buffer-live-p buffer)
             (eq (window-buffer (selected-window)) buffer))
    (with-current-buffer buffer
      ;; The page half: make the helper textarea `document.activeElement'.  Both
      ;; halves are required -- `xwHasFocus()' in nsxwidget.m checks the DOM side
      ;; before handing the key event to WebKit.
      (ignore-errors (ghostty-web-term--eval "window.gw && window.gw.focus()"))
      (ghostty-web-term--take-keyboard buffer))))

(defun ghostty-web-term--autofocus-on-selection-change (&optional _frame)
  "Hand the keyboard to a terminal whose window has just been selected."
  (let ((buf (ghostty-web-term--autofocus-eligible-p)))
    (when buf
      ;; Deferred: moving first responder inside the command that selected the
      ;; window is asking for trouble, and the switch should have settled before
      ;; the keyboard follows it.
      (run-with-idle-timer 0 nil #'ghostty-web-term--autofocus-run buf))))

;;;###autoload
(define-minor-mode ghostty-web-term-autofocus-mode
  "Give a ghostty-web terminal the keyboard whenever its window is selected.

Without this, switching to the terminal's window leaves the keyboard with
Emacs and the page says so (\"Emacs has the keyboard -- click to type\"),
because only a mouse click can give a WKWebView first responder.  This mode
does it programmatically instead, through the focus module.

Understand the trade before enabling it.  Any command that selects the
terminal's window now also takes the keyboard away from Emacs -- `other-window'
into it, a jump, `winner-undo', some package calling `pop-to-buffer' -- and the
only way back is a handoff chord (`ghostty-web-term-handoff-chords').  That is
the point of the feature and also its whole hazard.  Prompts, keyboard macros
and half-typed prefix sequences are excluded (see
`ghostty-web-term--autofocus-eligible-p'), but ordinary window motion is not.

Off by default, and inert if the focus module cannot be loaded."
  :global t
  :lighter nil
  (if ghostty-web-term-autofocus-mode
      (add-hook 'window-selection-change-functions
                #'ghostty-web-term--autofocus-on-selection-change)
    (remove-hook 'window-selection-change-functions
                 #'ghostty-web-term--autofocus-on-selection-change)))

;;; Page control channel

(defun ghostty-web-term--session ()
  "Return the xwidget to drive: this buffer's own, else a terminal's.
Deliberately not `xwidget-webkit-current-session', which falls back to the
last session used anywhere and so returns non-nil in every buffer, quite
possibly some unrelated widget.  The fallback here is narrower and is the
point: `ghostty-web-term-send-region' and friends are meant to be called
from the buffer you are editing, and should reach the terminal from there."
  (or (ghostty-web-term--buffer-xwidget (current-buffer))
      (seq-some #'ghostty-web-term--buffer-xwidget (ghostty-web-term--buffers))
      (user-error "ghostty-web-term: no terminal to talk to")))

(defun ghostty-web-term--eval (script &optional callback)
  "Run SCRIPT in the terminal page, optionally passing the result to CALLBACK."
  (xwidget-webkit-execute-script (ghostty-web-term--session) script callback))

(defun ghostty-web-term-focus ()
  "Give the keyboard to the terminal.

Also selects the terminal's window.  That matters: a handoff transfers the
keyboard to Emacs but does not change which window Emacs has selected.  If
selection has drifted elsewhere -- a preview buffer popping up, say -- then the
first `C-w h' after a handoff operates from that other window and looks broken
even though the handoff worked.  Keeping selection on the terminal while it owns
the keyboard preserves the invariant that handing off leaves you in the
terminal's window.

Whether this really hands over the keyboard depends on the focus module: with
it, first responder moves too and typing goes to the shell immediately; without
it, all Emacs can do is focus the page's textarea, and a click is still needed.
See `ghostty-web-term--focus-module-ensure'.

Afterwards Emacs bindings in this buffer will not fire until you press a handoff
chord (`ghostty-web-term-handoff-chords')."
  (interactive)
  (let ((win (get-buffer-window (current-buffer))))
    (when (and win (not (eq win (selected-window))))
      (select-window win)))
  (ghostty-web-term--eval "window.gw && window.gw.focus()")
  (if (ghostty-web-term--take-keyboard)
      (message "ghostty-web-term: terminal has the keyboard (%s hands it back)"
               ghostty-web-term-handoff-chords)
    ;; Without the module this cannot claim the terminal has the keyboard.  All
    ;; it did was focus the page's textarea, which is half of the condition: if
    ;; Emacs is still the window's first responder the keystrokes go to Emacs,
    ;; and no amount of Lisp or JavaScript changes that -- see the Commentary.
    (message
     "ghostty-web-term: terminal focused; if keys still go to Emacs, click it (%s hands back)"
     ghostty-web-term-handoff-chords)))

(defun ghostty-web-term-select ()
  "Select the terminal's window without taking the keyboard.
Use when Emacs's selected window has drifted away from the terminal, so that
window motions operate from the terminal instead of somewhere else."
  (interactive)
  (let* ((buf (seq-find (lambda (b) (buffer-local-value 'ghostty-web-term-mode b))
                        (buffer-list)))
         (win (and buf (get-buffer-window buf))))
    (cond ((null buf) (user-error "ghostty-web-term: no terminal buffer"))
          ((null win) (pop-to-buffer buf))
          (t (select-window win)))
    (message "ghostty-web-term: selected %s"
             (buffer-name (window-buffer (selected-window))))))

(defun ghostty-web-term-blur ()
  "Take the keyboard back from the terminal."
  (interactive)
  (ghostty-web-term--eval "window.gw && window.gw.blur()"))

(defun ghostty-web-term-send-string (string)
  "Send STRING to the shell as if typed."
  (interactive "sSend to terminal: ")
  ;; json-encode produces a correctly escaped JS string literal.
  (ghostty-web-term--eval
   (format "window.gw && window.gw.input(%s)" (json-encode string))))

(defun ghostty-web-term-send-region (start end &optional no-newline)
  "Send the region between START and END to the shell.
With a prefix argument (NO-NEWLINE), do not append a trailing newline."
  (interactive "r\nP")
  (let ((text (buffer-substring-no-properties start end)))
    (ghostty-web-term-send-string
     (if no-newline text (concat text "\n")))))

(defun ghostty-web-term-send-line ()
  "Send the current line to the shell."
  (interactive)
  (ghostty-web-term-send-region
   (line-beginning-position) (line-end-position)))

(defun ghostty-web-term-cd (directory)
  "Send a cd command for DIRECTORY to the shell."
  (interactive "DDirectory: ")
  (ghostty-web-term-send-string
   (format "cd %s\n" (shell-quote-argument (expand-file-name directory)))))

(defcustom ghostty-web-term-bracketed-paste t
  "Wrap multi-line pastes in bracketed-paste markers.
Without this a multi-line paste is executed line by line as it arrives,
so a pasted multi-line command runs before you can edit it.  Single-line
pastes are always sent raw, so this only matters when it needs to.

The markers are only emitted when the application actually enabled
bracketed paste (DECSET 2004); that check happens in the page, which is
the only side that knows the terminal's mode state.  Sending them
unconditionally would deliver a literal \"[200~\" into any shell or
program that had not asked for them.  Set this to nil to never bracket."
  :type 'boolean)

(defun ghostty-web-term--selection-text ()
  "Return the system clipboard as a non-empty string, or nil.
Reads the selection directly, so it neither signals nor disturbs the kill
ring or `gui-selection-value''s changed-since-last-look bookkeeping --
consuming that would make a later `current-kill' miss a fresh clipboard.

The data type matters: on the macOS NS port `UTF8_STRING' and `TEXT' both
come back as the empty string, and only the default type actually yields
the pasteboard contents."
  (let ((text (ignore-errors (gui-get-selection 'CLIPBOARD))))
    (and (stringp text) (not (string-empty-p text)) text)))

(defun ghostty-web-term--clipboard-text ()
  "Return the text to paste: the system clipboard, else the kill ring."
  (or (ghostty-web-term--selection-text)
      (ignore-errors (current-kill 0 t))
      (user-error "ghostty-web-term: nothing to paste")))

(defun ghostty-web-term--clipboard-text-quiet ()
  "Return the system clipboard as a string, or nil.
Unlike `ghostty-web-term--clipboard-text' this never signals and never
touches the kill ring, so it is safe to call from a timer."
  (ghostty-web-term--selection-text))

(defun ghostty-web-term-paste ()
  "Paste the clipboard into the shell.
Cmd-V cannot work natively here: ghostty-web returns early on Cmd-V so the
browser will perform its own paste, but an Emacs xwidget never generates
that native paste event.  So Emacs reads the clipboard and pushes the text
through the page's control channel instead.

Bracketing is left to the page, which checks the terminal's real DECSET
2004 state -- see `ghostty-web-term-bracketed-paste'."
  (interactive)
  (let* ((text (ghostty-web-term--clipboard-text))
         (fn (if ghostty-web-term-bracketed-paste "paste" "input")))
    (ghostty-web-term--eval
     (format "window.gw ? String(window.gw.%s(%s)) : 'no-gw'" fn (json-encode text))
     (lambda (result)
       (if (equal result "no-gw")
           (message "ghostty-web-term: page not ready (no window.gw) -- nothing pasted")
         (message "ghostty-web-term: pasted %d char%s"
                  (length text) (if (= 1 (length text)) "" "s")))))))

;;; Serving paste requests from the page
;;
;; The page cannot read the clipboard (see the Commentary), so its Cmd-V arrives
;; here as a request and Emacs answers with the clipboard as it is at that moment.
;; Nothing is cached, which is the point: a dictation or clipboard-manager tool
;; that copies and immediately presses Cmd-V would beat any cache.

(defun ghostty-web-term--buffers ()
  "Return the live buffers showing a ghostty-web terminal."
  (seq-filter (lambda (b) (buffer-local-value 'ghostty-web-term-mode b))
              (buffer-list)))

(defun ghostty-web-term--buffer-xwidget (buffer)
  "Return BUFFER's own xwidget, or nil.
Deliberately not `xwidget-webkit-current-session': that falls back to the
last session used, so it would happily return some other buffer's widget."
  (with-current-buffer buffer
    (and (derived-mode-p 'xwidget-webkit-mode)
         (xwidget-at (point-min)))))

(defun ghostty-web-term--buffer-for-client (client)
  "Return the terminal buffer whose page identifies itself as CLIENT.
Falls back to the sole terminal when CLIENT is missing or unknown, so a
page from before client ids existed still gets served."
  (let ((bufs (ghostty-web-term--buffers)))
    (or (and client
             (stringp client)
             (not (string-empty-p client))
             (seq-find (lambda (b)
                         (equal client (buffer-local-value
                                        'ghostty-web-term--client-id b)))
                       bufs))
        (and (= 1 (length bufs)) (car bufs)))))

(defun ghostty-web-term--serve-paste-request (client &optional buffer)
  "Send the current clipboard to the page identified by CLIENT.
BUFFER, when given, is the terminal the request provably came from -- the
server that relayed it serves that one terminal and no other -- and is
preferred over matching CLIENT."
  (let ((buf (or (and (buffer-live-p buffer) buffer)
                 (ghostty-web-term--buffer-for-client client))))
    (cond
     ((null buf)
      (message "ghostty-web-term: paste request from unknown client %S" client))
     (t
      (let ((text (ghostty-web-term--selection-text))
            (xw (ghostty-web-term--buffer-xwidget buf)))
        (cond
         ((null xw)
          (message "ghostty-web-term: paste request but no xwidget in %s"
                   (buffer-name buf)))
         ((null text)
          (ignore-errors
            (xwidget-webkit-execute-script
             xw "window.gw && window.gw.notifyEmpty && window.gw.notifyEmpty()")))
         (t
          (let ((fn (if ghostty-web-term-bracketed-paste "paste" "input")))
            (ignore-errors
              (xwidget-webkit-execute-script
               xw (format "window.gw && window.gw.%s(%s)" fn (json-encode text))))))))))))


(defun ghostty-web-term-copy ()
  "Copy the terminal's selection into the kill ring."
  (interactive)
  (ghostty-web-term--eval
   "window.gw ? window.gw.getSelection() : \"\""
   (lambda (text)
     (if (and (stringp text) (not (string-empty-p text)))
         (progn (kill-new text)
                (message "ghostty-web-term: copied %d chars" (length text)))
       (message "ghostty-web-term: no selection in terminal")))))

;;; Control plane: an Emacs-hosted WebSocket the page talks back on
;;
;; Emacs already has a good channel *to* the page (`xwidget-webkit-execute-script').
;; What was missing was a channel *from* it, which previously borrowed the PTY
;; server's stdout -- control traffic multiplexed onto a log stream, with no way to
;; correlate a request with its answer.  This is that channel, hosted by Emacs, so
;; the page talks to Emacs directly and either side can start a message.
;;
;; Deliberately the CONTROL plane only.  The terminal's data stream stays on the
;; Node PTY socket, because moving it here would put elisp WebSocket framing in the
;; path of every chunk of shell output -- a throughput risk on anything like
;; `cat bigfile'.  Control messages are small and rare, so framing cost is
;; irrelevant for them.  Fast path stays native; chatty path becomes clean.
;;
;; The wire format is one JSON object per text frame, both directions.  Only what
;; RFC 6455 requires for that is implemented: the handshake, unmasking client
;; frames, emitting unmasked server frames, ping/pong and close.  No fragmentation
;; reassembly beyond continuation of text, and no permessage-deflate.

(defconst ghostty-web-term--ws-guid "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  "Magic GUID from RFC 6455 used to derive the handshake accept token.")

(defvar ghostty-web-term--control-process nil
  "The listening control-plane server process, or nil.")

(defvar ghostty-web-term--control-port nil
  "Port the control server is listening on.")

(defvar ghostty-web-term--control-token nil
  "Shared secret a page must present to use the control channel.")

(defvar ghostty-web-term--control-clients nil
  "Alist of (CLIENT-ID . PROCESS) for pages currently connected.")

(defcustom ghostty-web-term-control-debug nil
  "When non-nil, log every control-plane message to `*ghostty-web-control*'.
Off by default: this is a debugging tap, and terminal traffic can include
things you would not want written to a buffer."
  :type 'boolean)

(defcustom ghostty-web-term-echo-input nil
  "When non-nil, ask pages to echo terminal input over the control channel.
Strictly a debugging aid, and off by default for two reasons: every
keystroke becomes a message through an Emacs process filter, and
keystrokes include passwords."
  :type 'boolean)

(defun ghostty-web-term--control-log (fmt &rest args)
  "Append a formatted message to the control-plane log when debugging."
  (when ghostty-web-term-control-debug
    (with-current-buffer (get-buffer-create "*ghostty-web-control*")
      (goto-char (point-max))
      (insert (apply #'format fmt args) "\n"))))

;;;; RFC 6455 bits

(defun ghostty-web-term--ws-accept (key)
  "Return the Sec-WebSocket-Accept value for client handshake KEY."
  (base64-encode-string
   (secure-hash 'sha1 (concat key ghostty-web-term--ws-guid) nil nil t)))

(defun ghostty-web-term--ws-frame (payload &optional opcode)
  "Wrap PAYLOAD in an unmasked server frame.  OPCODE defaults to text (1)."
  (let* ((data (encode-coding-string payload 'utf-8 t))
         (len (length data))
         (op (logior #x80 (or opcode 1)))
         (header
          (cond
           ((< len 126) (unibyte-string op len))
           ((< len 65536)
            (unibyte-string op 126 (logand (ash len -8) #xff) (logand len #xff)))
           (t
            (apply #'unibyte-string op 127
                   (mapcar (lambda (shift) (logand (ash len shift) #xff))
                           '(-56 -48 -40 -32 -24 -16 -8 0)))))))
    (concat header data)))

(defun ghostty-web-term--ws-take-frame (buf)
  "Try to peel one frame off the unibyte string BUF.
Return (OPCODE PAYLOAD REST) or nil when BUF holds no complete frame."
  (let ((n (length buf)))
    (when (>= n 2)
      (let* ((b0 (aref buf 0))
             (b1 (aref buf 1))
             (opcode (logand b0 #x0f))
             (masked (/= 0 (logand b1 #x80)))
             (len7 (logand b1 #x7f))
             (pos 2)
             len)
        (cond
         ((< len7 126) (setq len len7))
         ((= len7 126)
          (when (< n 4) (setq len nil))
          (when (>= n 4)
            (setq len (logior (ash (aref buf 2) 8) (aref buf 3)) pos 4)))
         (t
          (when (>= n 10)
            (setq len 0)
            (dotimes (i 8) (setq len (logior (ash len 8) (aref buf (+ 2 i)))))
            (setq pos 10))))
        (when len
          (let ((mask-len (if masked 4 0)))
            (when (>= n (+ pos mask-len len))
              (let* ((mask (and masked (substring buf pos (+ pos 4))))
                     (start (+ pos mask-len))
                     (raw (substring buf start (+ start len))))
                (when masked
                  (setq raw (apply #'unibyte-string
                                   (cl-loop for i from 0 below len
                                            collect (logxor (aref raw i)
                                                            (aref mask (mod i 4)))))))
                (list opcode raw (substring buf (+ start len)))))))))))

;;;; Connection handling

(defun ghostty-web-term--control-send (proc obj)
  "Send OBJ, a Lisp object encodable as JSON, to page PROC."
  (when (process-live-p proc)
    (ghostty-web-term--control-log "-> %s" (json-encode obj))
    (process-send-string proc (ghostty-web-term--ws-frame (json-encode obj)))))

(defun ghostty-web-term-control-broadcast (obj)
  "Send OBJ to every connected page."
  (dolist (cell ghostty-web-term--control-clients)
    (ghostty-web-term--control-send (cdr cell) obj)))

(defun ghostty-web-term--control-client-for (client)
  "Return the live control connection for CLIENT id, or nil."
  (let ((proc (cdr (assoc client ghostty-web-term--control-clients))))
    (and (process-live-p proc) proc)))

(defun ghostty-web-term--control-handle (proc text)
  "Dispatch one control message TEXT received from page PROC."
  (ghostty-web-term--control-log "<- %s" text)
  (let* ((msg (ignore-errors (json-parse-string text :object-type 'plist)))
         (type (and msg (plist-get msg :type))))
    (cond
     ((null msg) nil)
     ;; The page introduces itself so requests can be attributed to a buffer.
     ((equal type "hello")
      (let ((client (plist-get msg :client)))
        (process-put proc 'gw-client client)
        (setf (alist-get client ghostty-web-term--control-clients nil nil #'equal) proc)
        (ghostty-web-term--control-send
         proc (list :type "hello-ack" :echoInput (if ghostty-web-term-echo-input t :false)))))
     ;; The whole point: Emacs reads the clipboard *now* and sends it back.
     ((equal type "paste-request")
      (let ((clip (ghostty-web-term--selection-text)))
        (ghostty-web-term--control-send
         proc (if clip
                  (list :type "paste"
                        :data clip
                        :bracket (if ghostty-web-term-bracketed-paste t :false))
                (list :type "paste-empty")))))
     ((equal type "handoff")
      (ghostty-web-term--deliver-chord (plist-get msg :chord)))
     ((equal type "input-echo")
      (ghostty-web-term--control-log "input-echo %S" (plist-get msg :data)))
     ((equal type "log")
      (message "ghostty-web-term[page]: %s" (plist-get msg :text)))
     (t (ghostty-web-term--control-log "unhandled type %S" type)))))

(defun ghostty-web-term--control-filter (proc chunk)
  "Feed CHUNK from PROC through the handshake, then the frame parser."
  (process-put proc 'gw-buf (concat (or (process-get proc 'gw-buf) "") chunk))
  (if (not (process-get proc 'gw-open))
      ;; Still expecting the HTTP upgrade request.
      (let ((buf (process-get proc 'gw-buf)))
        (when (string-match "\r\n\r\n" buf)
          (let* ((head (substring buf 0 (match-beginning 0)))
                 (rest (substring buf (match-end 0)))
                 (key (and (string-match "Sec-WebSocket-Key:[ \t]*\\([^\r\n]+\\)" head)
                           (string-trim (match-string 1 head))))
                 (tok (and (string-match "token=\\([A-Za-z0-9]+\\)" head)
                           (match-string 1 head))))
            (if (not (and key tok ghostty-web-term--control-token
                          (string= tok ghostty-web-term--control-token)))
                ;; Anything that can drive the page and read terminal traffic has
                ;; to be gated; an unauthenticated local port here would be an
                ;; injection channel into a live shell.
                (progn
                  (process-send-string
                   proc "HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n")
                  (delete-process proc))
              (process-send-string
               proc (concat "HTTP/1.1 101 Switching Protocols\r\n"
                            "Upgrade: websocket\r\n"
                            "Connection: Upgrade\r\n"
                            "Sec-WebSocket-Accept: "
                            (ghostty-web-term--ws-accept key) "\r\n\r\n"))
              (process-put proc 'gw-open t)
              (process-put proc 'gw-buf rest)
              (ghostty-web-term--control-filter proc "")))))
    ;; Handshaken: pull off as many whole frames as have arrived.
    (let (frame)
      (while (setq frame (ghostty-web-term--ws-take-frame (process-get proc 'gw-buf)))
        (let ((opcode (nth 0 frame))
              (payload (nth 1 frame)))
          (process-put proc 'gw-buf (nth 2 frame))
          (cond
           ((memq opcode '(1 0))
            (ghostty-web-term--control-handle
             proc (decode-coding-string payload 'utf-8)))
           ((= opcode 8) (delete-process proc))
           ((= opcode 9)
            (process-send-string proc (ghostty-web-term--ws-frame "" 10)))))))))

(defun ghostty-web-term--control-sentinel (proc _event)
  "Forget PROC when its connection ends."
  (unless (process-live-p proc)
    (let ((client (process-get proc 'gw-client)))
      (when client
        (setq ghostty-web-term--control-clients
              (assoc-delete-all client ghostty-web-term--control-clients))))))

(defun ghostty-web-term--control-ensure ()
  "Start the control server if needed.  Return (PORT . TOKEN)."
  (unless (and ghostty-web-term--control-process
               (process-live-p ghostty-web-term--control-process))
    (setq ghostty-web-term--control-token
          (let ((s ""))
            (dotimes (_ 32) (setq s (concat s (format "%x" (random 16)))))
            s)
          ghostty-web-term--control-clients nil)
    (setq ghostty-web-term--control-process
          (make-network-process
           :name "ghostty-web-control"
           :server t
           :host 'local                 ; loopback only
           :service t                   ; let the OS pick a port
           :family 'ipv4
           :noquery t
           :coding '(binary . binary)
           :filter #'ghostty-web-term--control-filter
           :sentinel #'ghostty-web-term--control-sentinel))
    (setq ghostty-web-term--control-port
          (process-contact ghostty-web-term--control-process :service)))
  (cons ghostty-web-term--control-port ghostty-web-term--control-token))

(defun ghostty-web-term-control-stop ()
  "Shut the control server down and forget its clients.

The control channel is one listener multiplexing every page by client id, so
unlike the PTY servers it is not owned by a buffer and nothing stops it when
a terminal is killed; it is cheap, and `ghostty-web-term--control-ensure'
brings it back (on a new port, with a new token) for the next terminal.
Pages whose channel this drops fall back to relaying paste requests through
their own PTY server's stdout."
  (interactive)
  (dolist (cell ghostty-web-term--control-clients)
    (ignore-errors (delete-process (cdr cell))))
  (setq ghostty-web-term--control-clients nil)
  (when (and ghostty-web-term--control-process
             (process-live-p ghostty-web-term--control-process))
    (ignore-errors (delete-process ghostty-web-term--control-process)))
  (setq ghostty-web-term--control-process nil
        ghostty-web-term--control-port nil
        ghostty-web-term--control-token nil))

(defun ghostty-web-term-control-status ()
  "Report the control channel's state."
  (interactive)
  (message "ghostty-web-term: control port=%s clients=%S debug=%s"
           ghostty-web-term--control-port
           (mapcar #'car ghostty-web-term--control-clients)
           ghostty-web-term-control-debug))

(defun ghostty-web-term-control-ping (client)
  "Ask page CLIENT to report its state over the control channel.
Handy for checking the channel end to end from Emacs."
  (interactive (list (or (caar ghostty-web-term--control-clients)
                         (read-string "Client: "))))
  (let ((proc (ghostty-web-term--control-client-for client)))
    (if (not proc)
        (message "ghostty-web-term: no control connection for client %s" client)
      (ghostty-web-term--control-send proc (list :type "ping-state"))
      (message "ghostty-web-term: asked client %s for state" client))))

;;;; Handoff chord delivery
;;
;; A handoff chord used to only give the keyboard back, so `C-w' in the terminal
;; reached Emacs as *nothing*: you pressed it once to hand off and again to start
;; Emacs's window prefix.  The page now also reports which chord fired, and Emacs
;; feeds that key to its own command loop, so one press hands off and opens the
;; chord.

(defcustom ghostty-web-term-handoff-delivers-chord t
  "When non-nil, a handoff chord is also delivered to Emacs.
So `C-w' in the terminal hands the keyboard back *and* begins Emacs's
`C-w' prefix, instead of needing a second press.  The key is pushed onto
`unread-command-events', which is the only way in: Emacs cannot receive a
synthesized key event from the page itself."
  :type 'boolean)

(defconst ghostty-web-term--chord-modifiers
  '(("ctrl" . "C-") ("alt" . "M-") ("meta" . "s-") ("shift" . "S-"))
  "Map from the page's modifier names to Emacs key-description prefixes.")

(defconst ghostty-web-term--chord-keys
  '(("Escape" . "<escape>") ("Tab" . "TAB") ("Enter" . "RET")
    ("Backspace" . "DEL") ("Delete" . "<delete>") ("Space" . "SPC")
    ("ArrowUp" . "<up>") ("ArrowDown" . "<down>")
    ("ArrowLeft" . "<left>") ("ArrowRight" . "<right>"))
  "Map from KeyboardEvent key names to Emacs key-description names.")

(defun ghostty-web-term--chord-to-key (chord)
  "Translate CHORD, e.g. \"ctrl-w\", into an Emacs key description or nil."
  (when (and (stringp chord) (not (string-empty-p chord)))
    (let* ((parts (split-string chord "-" t))
           (key (car (last parts)))
           (mods (butlast parts))
           (prefix ""))
      (dolist (m mods)
        (let ((p (cdr (assoc-string m ghostty-web-term--chord-modifiers t))))
          (if p (setq prefix (concat prefix p))
            (setq prefix nil))))
      (when prefix
        (let ((name (or (cdr (assoc-string key ghostty-web-term--chord-keys t))
                        (and (= 1 (length key)) key))))
          (and name (concat prefix name)))))))

(defun ghostty-web-term--deliver-chord (chord)
  "Feed CHORD to Emacs's command loop as if it had been typed here."
  (when ghostty-web-term-handoff-delivers-chord
    (let* ((desc (ghostty-web-term--chord-to-key chord))
           (keys (and desc (ignore-errors (listify-key-sequence (kbd desc))))))
      (when keys
        ;; Slightly deferred: the page posts "C-g" to take first responder away
        ;; at the same moment, and the prefix must not start reading its next key
        ;; before Emacs actually owns the keyboard.
        (run-with-timer
         0.05 nil
         (lambda ()
           (setq unread-command-events
                 (append unread-command-events keys))))
        t))))

;;; Zoom

(defun ghostty-web-term--set-font-size (px)
  "Set the terminal font size to PX and refit the grid."
  (setq ghostty-web-term-font-size (max 6 (min 48 px)))
  ;; `setFontSize' refits itself, and does it again once the renderer has
  ;; remeasured -- a fit from here would only report the pre-measurement grid.
  (ghostty-web-term--eval
   (format "window.gw && String(window.gw.setFontSize(%d))"
           ghostty-web-term-font-size))
  (message "ghostty-web-term: font size %d" ghostty-web-term-font-size))

(defun ghostty-web-term-zoom-in (&optional step)
  "Increase the terminal font size by STEP pixels (default 1).
Emacs text scaling cannot affect the terminal: the widget's pixel size is
unchanged by zooming, so the grid never resizes.  Scaling the page font is
the equivalent operation."
  (interactive "p")
  (ghostty-web-term--set-font-size (+ ghostty-web-term-font-size (or step 1))))

(defun ghostty-web-term-zoom-out (&optional step)
  "Decrease the terminal font size by STEP pixels (default 1)."
  (interactive "p")
  (ghostty-web-term--set-font-size (- ghostty-web-term-font-size (or step 1))))

(defun ghostty-web-term-zoom-reset ()
  "Reset the terminal font size to 13px, and undo any view magnification."
  (interactive)
  (ghostty-web-term--set-font-size 13)
  (ghostty-web-term-zoom-native-reset))

(defun ghostty-web-term-zoom-native-reset ()
  "Undo WebKit view magnification, leaving font size as the only zoom.
`xwidget-webkit-zoom' scales the rendered view without reflowing it: dpr and
`innerWidth' change, `clientWidth' does not, so no `ResizeObserver' fires and a
stale grid is drawn magnified and clipped.  The keymap redirects the zoom keys,
but the Zoom In/Out menu and tool bar items still reach it, and magnification
survives a page reload -- hence a way back.  Only the page can report how far
the view is scaled, so this is asynchronous."
  (interactive)
  (let ((xw (ghostty-web-term--session)))
    (when xw
      (xwidget-webkit-execute-script
       xw "window.gw ? String(window.gw.magnification()) : ''"
       (lambda (result)
         (let ((mag (and (stringp result) (string-to-number result))))
           (when (and mag (> mag 0) (> (abs (- mag 1.0)) 0.01))
             ;; Additive on magnification: three +0.1 steps take dpr 2 -> 2.6.
             (xwidget-webkit-zoom xw (- 1.0 mag))
             (xwidget-webkit-execute-script
              xw "window.gw && JSON.stringify(window.gw.fit())"))))))))

(defun ghostty-web-term-resync-size ()
  "Resize the widget to its window and refit the terminal grid.
`window-size-change-functions' already resizes xwidgets, but call this after
anything that leaves the grid out of step with the widget."
  (interactive)
  (let ((xw (xwidget-webkit-current-session)))
    (when xw
      (xwidget-webkit-adjust-size-to-window xw (get-buffer-window (current-buffer)))))
  (ghostty-web-term--eval "window.gw && JSON.stringify(window.gw.fit())"))

(defun ghostty-web-term-fit ()
  "Ask the page to refit the terminal grid to the widget."
  (interactive)
  (ghostty-web-term--eval "window.gw && JSON.stringify(window.gw.fit())"))

(defun ghostty-web-term-state ()
  "Report the terminal's current state in the echo area."
  (interactive)
  (ghostty-web-term--eval
   "window.gw ? JSON.stringify(window.gw.state()) : 'no gw'"
   (lambda (result) (message "ghostty-web-term: %s" result))))

;;; Entry point

(defvar-keymap ghostty-web-term-mode-map
  :doc "Keymap active in a ghostty-web terminal buffer.

Every binding here, super-key ones included, only fires while Emacs
holds the keyboard (see `ghostty-web-term-handoff-chords').  While the
terminal holds it the widget is first responder and even Cmd chords go
to WebKit, so nothing in this map is reachable then; Cmd-V is handled
inside the page for that case."
  "C-c C-f" #'ghostty-web-term-focus
  "C-c C-k" #'ghostty-web-term-blur
  "C-c C-r" #'ghostty-web-term-restart-server
  "C-c C-s" #'ghostty-web-term-state
  "C-c C-w" #'ghostty-web-term-fit
  "C-c C-y" #'ghostty-web-term-paste
  "C-c M-w" #'ghostty-web-term-copy
  "C-c C-o" #'ghostty-web-term-select
  "s-v" #'ghostty-web-term-paste
  "s-c" #'ghostty-web-term-copy
  "s-e" #'ghostty-web-term-blur
  "s-t" #'ghostty-web-term-select
  ;; Emacs text scaling cannot resize the widget, so redirect the usual zoom
  ;; commands to the terminal's own font size.  The WebKit ones too: they only
  ;; change the view's magnification, which leaves `clientWidth' -- and so the
  ;; grid -- untouched, magnifying a stale 80x31 into a clipped canvas.
  "<remap> <text-scale-increase>" #'ghostty-web-term-zoom-in
  "<remap> <text-scale-decrease>" #'ghostty-web-term-zoom-out
  "<remap> <text-scale-adjust>" #'ghostty-web-term-zoom-reset
  "<remap> <xwidget-webkit-zoom-in>" #'ghostty-web-term-zoom-in
  "<remap> <xwidget-webkit-zoom-out>" #'ghostty-web-term-zoom-out
  "s-=" #'ghostty-web-term-zoom-in
  "s-+" #'ghostty-web-term-zoom-in
  "s--" #'ghostty-web-term-zoom-out
  "s-0" #'ghostty-web-term-zoom-reset
  "C-c C-=" #'ghostty-web-term-zoom-in
  "C-c C--" #'ghostty-web-term-zoom-out)

(defun ghostty-web-term--kill-buffer-hook ()
  "Take this terminal's server down with the buffer.
The shell dies either way -- the server kills its PTY when the page's
WebSocket closes -- but the node process is this buffer's, and once the
buffer is gone nothing else would ever notice it is serving nobody.

This is the whole of server lifetime management.  An earlier version
reference-counted a shared server against the live terminal buffers from a
timer, which could not work retroactively: buffers opened before the hook
existed never ran the mode body that installs it, so they never stopped
anything.  A server owned by one buffer has no such gap."
  (ghostty-web-term--server-kill ghostty-web-term--server))

(define-minor-mode ghostty-web-term-mode
  "Minor mode for buffers showing a ghostty-web terminal."
  :lighter " Ghostty"
  :keymap ghostty-web-term-mode-map
  (if ghostty-web-term-mode
      (progn
        ;; Zoom is per terminal: each buffer drives its own page, so a shared
        ;; counter would step the next terminal from the wrong size -- zoom one
        ;; to 20px and the first `=' in another jumps its 13px page to 21.  The
        ;; defcustom stays the size new terminals open at.
        (setq-local ghostty-web-term-font-size ghostty-web-term-font-size)
        (add-hook 'kill-buffer-hook #'ghostty-web-term--kill-buffer-hook nil t))
    (remove-hook 'kill-buffer-hook #'ghostty-web-term--kill-buffer-hook t)))

;; Evil's state keymaps outrank ordinary minor-mode maps, so register the
;; bindings with evil too when it is present (it is, under Doom).
(with-eval-after-load 'evil
  (when (fboundp 'evil-define-minor-mode-key)
    (dolist (state '(normal motion insert emacs))
      (evil-define-minor-mode-key state 'ghostty-web-term-mode
        (kbd "s-v") #'ghostty-web-term-paste
        (kbd "s-c") #'ghostty-web-term-copy
        (kbd "s-e") #'ghostty-web-term-blur
        (kbd "s-t") #'ghostty-web-term-select))))

(defun ghostty-web-term--url (client server)
  "Build the page URL for CLIENT on SERVER.
Carries SERVER's token, the control channel's port and token, and the
display preferences."
  (let* ((base (plist-get (ghostty-web-term--server-info server) :url))
         (control (ghostty-web-term--control-ensure)))
    (format (concat "%s&fontSize=%d&handoffChords=%s&wheelAltScreen=%s"
                    "&wheelSensitivity=%s&client=%s&ctrlPort=%s&ctrlToken=%s")
            base
            ghostty-web-term-font-size
            (url-hexify-string ghostty-web-term-handoff-chords)
            (url-hexify-string ghostty-web-term-alt-screen-wheel)
            (number-to-string ghostty-web-term-wheel-sensitivity)
            (url-hexify-string client)
            (car control)
            (url-hexify-string (cdr control)))))

;;;###autoload
(defun ghostty-web-term (&optional new-session)
  "Open a Ghostty terminal in an xwidget buffer.
With a prefix argument NEW-SESSION, start an additional terminal
instead of reusing an existing one.

Each terminal gets its own PTY server, so opening one waits for a node
startup and its readiness handshake (about a second), and killing the buffer
takes that server with it."
  (interactive "P")
  (unless (featurep 'xwidget-internal)
    (user-error "ghostty-web-term: this Emacs was built without xwidget support"))
  (unless (display-graphic-p)
    (user-error "ghostty-web-term: xwidgets need a graphical frame"))
  (let ((existing (unless new-session (car (ghostty-web-term--buffers)))))
    (if existing
        (pop-to-buffer existing)
      (let* ((client (ghostty-web-term--next-client-id))
             (server (ghostty-web-term--server-start client))
             (adopted nil))
        (unwind-protect
            (progn
              (xwidget-webkit-browse-url (ghostty-web-term--url client server) t)
              ;; Find the new buffer explicitly instead of assuming `browse-url'
              ;; left it current -- it does interactively, but not when called
              ;; from contexts like `emacsclient --eval', where the mode would
              ;; land on the wrong buffer.
              ;; Do not rename it: the xwidget title callback renames the buffer
              ;; once the page loads and would clobber anything set here, so the
              ;; name comes from the page title (and tracks the shell's title
              ;; escapes).
              ;; Use `xwidget-webkit-last-session-buffer', which
              ;; `xwidget-webkit--create-new-session-buffer' just set.  Note
              ;; `xwidget-webkit-current-session' is NOT usable for this: it
              ;; falls back to the last session, so it returns non-nil in every
              ;; buffer and would happily identify an unrelated one.
              (let ((buf (or (and (boundp 'xwidget-webkit-last-session-buffer)
                                  (buffer-live-p xwidget-webkit-last-session-buffer)
                                  xwidget-webkit-last-session-buffer)
                             (and (derived-mode-p 'xwidget-webkit-mode)
                                  (current-buffer)))))
                (unless buf
                  (user-error "ghostty-web-term: could not find the new xwidget buffer"))
                (with-current-buffer buf
                  (ghostty-web-term-mode 1)
                  ;; Recorded so a message from this page is attributed to this
                  ;; buffer and not to some other terminal.
                  (setq ghostty-web-term--client-id client))
                ;; From here the buffer owns the server: killing it stops the
                ;; process.
                (ghostty-web-term--server-adopt server buf)
                (setq adopted t)
                (pop-to-buffer buf)))
          ;; Until the buffer owns it, nothing else knows this server exists, so
          ;; anything going wrong above would strand a node process.
          (unless adopted (ghostty-web-term--server-kill server))))))
  (message "ghostty-web-term: all keys go to the shell; %s hands the keyboard to Emacs"
           ghostty-web-term-handoff-chords))

(provide 'ghostty-web-term)
;;; ghostty-web-term.el ends here
