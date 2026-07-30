;;; ghostty-web-term.el --- Ghostty terminal in an Emacs xwidget -*- lexical-binding: t; -*-

;; Author: Kevin Krausse
;; Keywords: terminals, processes
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Runs a real shell inside an Emacs WebKit xwidget buffer, rendered by
;; ghostty-web (Ghostty's VT parser compiled to WASM).  A small Node server
;; provides the PTY over a loopback WebSocket; this file starts that server on
;; demand and points an xwidget at it.
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
;; turned into a paste *request*: the page sends it over the PTY WebSocket, the
;; server prints it on stdout, the Emacs process filter picks it up and answers with
;; the clipboard as it is right then (`ghostty-web-term--serve-paste-request').
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

(defvar ghostty-web-term--process nil
  "The running PTY server process, or nil.")

(defvar ghostty-web-term--info nil
  "Plist describing the running server: :url, :port, :token.")

(defvar ghostty-web-term--stdout ""
  "Accumulated server stdout, scanned for the readiness handshake.")

(defconst ghostty-web-term--ready-prefix "GHOSTTY_WEB_READY "
  "Prefix of the handshake line the server prints once listening.")

;;; Server lifecycle

(defun ghostty-web-term--server-live-p ()
  "Return non-nil when the PTY server process is running."
  (and ghostty-web-term--process
       (process-live-p ghostty-web-term--process)))

(defconst ghostty-web-term--paste-prefix "GHOSTTY_WEB_PASTE_REQUEST "
  "Prefix of the line the server prints when a page asks Emacs to paste.")

(defun ghostty-web-term--filter (proc string)
  "Handle STRING from the server PROC one complete line at a time.
Also echoes into the process buffer, so `*ghostty-web-server*' actually
shows the server's diagnostics -- setting a filter otherwise suppresses
them, which made the \"see *ghostty-web-server*\" advice useless."
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (save-excursion (goto-char (point-max)) (insert string))))))
  (setq ghostty-web-term--stdout (concat ghostty-web-term--stdout string))
  ;; Consume whole lines and keep only a partial tail, so the accumulator cannot
  ;; grow without bound and a line is never acted on twice.
  (while (string-match "\\`\\([^\n]*\\)\n" ghostty-web-term--stdout)
    (let ((line (match-string 1 ghostty-web-term--stdout)))
      (setq ghostty-web-term--stdout
            (substring ghostty-web-term--stdout (match-end 0)))
      (ghostty-web-term--handle-line line))))

(defun ghostty-web-term--handle-line (line)
  "Act on one complete output LINE from the server."
  (cond
   ((and (not ghostty-web-term--info)
         (string-prefix-p ghostty-web-term--ready-prefix line))
    (let* ((payload (substring line (length ghostty-web-term--ready-prefix)))
           (parsed (condition-case err
                       (json-parse-string payload :object-type 'plist)
                     (error
                      (message "ghostty-web-term: bad handshake: %S" err)
                      nil))))
      (when parsed
        (setq ghostty-web-term--info
              (list :url (plist-get parsed :url)
                    :port (plist-get parsed :port)
                    :token (plist-get parsed :token))))))
   ((string-prefix-p ghostty-web-term--paste-prefix line)
    (let* ((payload (substring line (length ghostty-web-term--paste-prefix)))
           (parsed (ignore-errors
                     (json-parse-string payload :object-type 'plist)))
           (client (and parsed (plist-get parsed :client))))
      (ghostty-web-term--serve-paste-request client)))))

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

(defun ghostty-web-term-start-server ()
  "Start the PTY server unless it is already running.  Return its info plist."
  (interactive)
  (if (ghostty-web-term--server-live-p)
      ghostty-web-term--info
    (ghostty-web-term--check-installed)
    (setq ghostty-web-term--stdout ""
          ghostty-web-term--info nil)
    (let* ((default-directory ghostty-web-term-directory)
           (args (append
                  (list "server.js" "--port" (number-to-string ghostty-web-term-port))
                  (when ghostty-web-term-command
                    (list "--cmd" ghostty-web-term-command))
                  (when ghostty-web-term-directory-for-shell
                    (list "--cwd" (expand-file-name
                                   ghostty-web-term-directory-for-shell))))))
      (setq ghostty-web-term--process
            (make-process
             :name "ghostty-web-server"
             :buffer (get-buffer-create "*ghostty-web-server*")
             :command (cons ghostty-web-term-node-program args)
             :connection-type 'pipe
             :noquery t
             :filter #'ghostty-web-term--filter
             :sentinel #'ghostty-web-term--sentinel)))
    ;; Block briefly for the handshake so callers get a usable URL.
    (let ((deadline (+ (float-time) ghostty-web-term-startup-timeout)))
      (while (and (not ghostty-web-term--info)
                  (ghostty-web-term--server-live-p)
                  (< (float-time) deadline))
        (accept-process-output ghostty-web-term--process 0.05)))
    (unless ghostty-web-term--info
      (let ((msg (if (ghostty-web-term--server-live-p)
                     "timed out waiting for server handshake"
                   "server exited during startup")))
        (user-error "ghostty-web-term: %s (see *ghostty-web-server*)" msg)))
    ghostty-web-term--info))

(defun ghostty-web-term--sentinel (_proc event)
  "Clear cached server info when the process ends.  EVENT is the status change."
  (unless (string-match-p "\\`\\(run\\|open\\)" event)
    (setq ghostty-web-term--info nil)))

(defun ghostty-web-term-stop-server ()
  "Stop the PTY server, killing every shell it is hosting."
  (interactive)
  (when (ghostty-web-term--server-live-p)
    (delete-process ghostty-web-term--process))
  (setq ghostty-web-term--process nil
        ghostty-web-term--info nil)
  (message "ghostty-web-term: server stopped"))

(defun ghostty-web-term-restart-server ()
  "Restart the PTY server."
  (interactive)
  (ghostty-web-term-stop-server)
  (ghostty-web-term-start-server)
  (message "ghostty-web-term: server restarted on port %s"
           (plist-get ghostty-web-term--info :port)))

;;; Page control channel

(defun ghostty-web-term--session ()
  "Return the xwidget in the current buffer, or signal."
  (or (xwidget-webkit-current-session)
      (user-error "ghostty-web-term: no xwidget in this buffer")))

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

Afterwards Emacs bindings in this buffer will not fire until you press a handoff
chord (`ghostty-web-term-handoff-chords')."
  (interactive)
  (let ((win (get-buffer-window (current-buffer))))
    (when (and win (not (eq win (selected-window))))
      (select-window win)))
  (ghostty-web-term--eval "window.gw && window.gw.focus()")
  ;; Deliberately does not claim the terminal now has the keyboard.  All this can
  ;; do is focus the page's textarea, which is only half of it: if Emacs is the
  ;; window's first responder the keystrokes still go to Emacs, and no Lisp can
  ;; change that -- see the commentary at the top of this file.
  (message
   "ghostty-web-term: terminal focused; if keys still go to Emacs, click it (%s hands back)"
   ghostty-web-term-handoff-chords))

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

(defvar-local ghostty-web-term--client-id nil
  "Identifier this buffer's page uses when asking Emacs to paste.")

(defvar ghostty-web-term--client-counter 0
  "Counter handing out `ghostty-web-term--client-id' values.")

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

(defun ghostty-web-term--serve-paste-request (client)
  "Send the current clipboard to the page identified by CLIENT."
  (let ((buf (ghostty-web-term--buffer-for-client client)))
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

(defun ghostty-web-term--control-stop ()
  "Shut the control server down and forget its clients."
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
  (ghostty-web-term--eval
   (format "window.gw && (window.gw.setFontSize(%d), JSON.stringify(window.gw.fit()))"
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
  "Reset the terminal font size to 13px."
  (interactive)
  (ghostty-web-term--set-font-size 13))

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
  ;; commands to the terminal's own font size.
  "<remap> <text-scale-increase>" #'ghostty-web-term-zoom-in
  "<remap> <text-scale-decrease>" #'ghostty-web-term-zoom-out
  "<remap> <text-scale-adjust>" #'ghostty-web-term-zoom-reset
  "s-=" #'ghostty-web-term-zoom-in
  "s-+" #'ghostty-web-term-zoom-in
  "s--" #'ghostty-web-term-zoom-out
  "s-0" #'ghostty-web-term-zoom-reset
  "C-c C-=" #'ghostty-web-term-zoom-in
  "C-c C--" #'ghostty-web-term-zoom-out)

(defcustom ghostty-web-term-stop-server-on-last-kill t
  "Stop the PTY server once the last terminal buffer is killed.

The server is a singleton shared by every terminal, not something owned by
a buffer, so killing a buffer does not by itself stop it.  The shell always
dies with its page -- the server kills the PTY when the WebSocket closes --
but the server process and Emacs\='s control socket would otherwise sit idle
until `ghostty-web-term-stop-server\='.

Set to nil to keep the server warm, which makes opening the next terminal
skip node startup and the readiness handshake."
  :type 'boolean)

(defun ghostty-web-term--maybe-stop-server ()
  "Stop the server when no terminal buffers are left.
Runs from a timer, not directly from `kill-buffer-hook\=': the buffer being
killed is still live while that hook runs, so counting there would always
find at least one."
  (run-with-timer
   0 nil
   (lambda ()
     (when (and ghostty-web-term-stop-server-on-last-kill
                (null (ghostty-web-term--buffers)))
       (ghostty-web-term--control-stop)
       (when (ghostty-web-term--server-live-p)
         (ghostty-web-term-stop-server))))))

(define-minor-mode ghostty-web-term-mode
  "Minor mode for buffers showing a ghostty-web terminal."
  :lighter " Ghostty"
  :keymap ghostty-web-term-mode-map
  (when ghostty-web-term-mode
    (add-hook 'kill-buffer-hook #'ghostty-web-term--maybe-stop-server nil t)))

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

(defun ghostty-web-term--url (client)
  "Build the page URL, carrying the token, display preferences and CLIENT id."
  (let* ((info (ghostty-web-term-start-server))
         (base (plist-get info :url))
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
instead of reusing an existing one."
  (interactive "P")
  (unless (featurep 'xwidget-internal)
    (user-error "ghostty-web-term: this Emacs was built without xwidget support"))
  (unless (display-graphic-p)
    (user-error "ghostty-web-term: xwidgets need a graphical frame"))
  (let ((existing (unless new-session
                    (seq-find (lambda (buf)
                                (buffer-local-value 'ghostty-web-term-mode buf))
                              (buffer-list)))))
    (if existing
        (pop-to-buffer existing)
      (let ((client (number-to-string
                     (setq ghostty-web-term--client-counter
                           (1+ ghostty-web-term--client-counter)))))
      (xwidget-webkit-browse-url (ghostty-web-term--url client) t)
      ;; Find the new buffer explicitly instead of assuming `browse-url' left it
      ;; current -- it does interactively, but not when called from contexts like
      ;; `emacsclient --eval', where the mode would land on the wrong buffer.
      ;; Do not rename it: the xwidget title callback renames the buffer once the
      ;; page loads and would clobber anything set here, so the name comes from
      ;; the page title (and tracks the shell's title escapes).
      ;; Use `xwidget-webkit-last-session-buffer', which
      ;; `xwidget-webkit--create-new-session-buffer' just set.  Note
      ;; `xwidget-webkit-current-session' is NOT usable for this: it falls back
      ;; to the last session, so it returns non-nil in every buffer and would
      ;; happily identify an unrelated one.
      (let ((buf (or (and (boundp 'xwidget-webkit-last-session-buffer)
                          (buffer-live-p xwidget-webkit-last-session-buffer)
                          xwidget-webkit-last-session-buffer)
                     (and (derived-mode-p 'xwidget-webkit-mode) (current-buffer)))))
        (unless buf
          (user-error "ghostty-web-term: could not find the new xwidget buffer"))
        (with-current-buffer buf
          (ghostty-web-term-mode 1)
          ;; Recorded so a paste request from this page is answered by this
          ;; buffer and not by some other terminal.
          (setq ghostty-web-term--client-id client))
        (pop-to-buffer buf)))))
  (message "ghostty-web-term: all keys go to the shell; %s hands the keyboard to Emacs"
           ghostty-web-term-handoff-chords))

(provide 'ghostty-web-term)
;;; ghostty-web-term.el ends here
