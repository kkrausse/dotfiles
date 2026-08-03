# ghostty-web-emacs

A real shell inside an Emacs WebKit xwidget buffer, rendered by
[ghostty-web](https://github.com/coder/ghostty-web) — Ghostty's VT parser
compiled to WASM.

Three pieces:

- `server/` — a loopback Node server. Serves the page and gives each WebSocket
  connection its own PTY.
- `ghostty-web-term.el` — starts one of those servers per terminal buffer and
  points that buffer's xwidget at it. See [Server lifetime](#server-lifetime).
- `module/gw-focus.m` — optional dynamic module making the one AppKit call the NS
  xwidget port is missing, so the keyboard can move into the terminal without a
  mouse click. See
  [Getting back into the terminal without clicking](#getting-back-into-the-terminal-without-clicking).

## Status

Working in a live Emacs xwidget buffer: on open the terminal owns the keyboard
(`focused: true`, `xwHasFocus(): true`), the PTY connects, and the shell
round-trips. Verified in Chrome too: real PTY (`/dev/ttysNN`), keyboard input,
correct `TERM`/`COLORTERM`, `tput cols`/`lines` matching the rendered grid,
truecolor and unicode. Server lifecycle (handshake, health, shutdown) verified
headlessly; the first-responder handoff verified live.

The wheel fix is verified in Chrome against a mouse-reporting app: wheel events
arrive as SGR reports (`^[[<65;13;6M` / `^[[<64;13;6M`) with no arrow keys.

## Setup

```bash
cd server && npm install
```

`npm install` needs a `postinstall` that runs `chmod +x` on node-pty's
`spawn-helper`: npm does not preserve the executable bit inside
`node_modules/node-pty/prebuilds/`, and without it every spawn fails with
`posix_spawnp failed`.

Then, in Doom's `config.el` (matching the existing `local-packages` convention):

```elisp
(load-file (expand-file-name "local-packages/ghostty-web-emacs/ghostty-web-term.el"
                             doom-user-dir))

;; Optional: the keyboard follows window selection into the terminal, so
;; switching to its window means you can type in it. Needs module/gw-focus.dylib,
;; which is compiled on demand. Read the trade-off first:
;; "Getting back into the terminal without clicking".
(ghostty-web-term-autofocus-mode 1)
```

Run `M-x ghostty-web-term`.

## How input works

This is the part that constrains the whole design, so it's worth knowing.

Emacs cannot synthesize key events into a WebKit xwidget on macOS. The only API
for it, `xwidget-perform-lispy-event`, has its entire body inside `#ifdef
USE_GTK` in `src/xwidget.c`. On an NS build (`emacs-plus`, `--with-ns`) it is a
no-op returning `nil`, which also means `xwidget-webkit-edit-mode` does nothing.

The NS port routes keys a different way. `src/nsxwidget.m` evaluates
`xwHasFocus()` on every `keyDown:`:

```objc
// true  -> [super keyDown:event]   raw native event goes to WebKit
// false -> forward the event to Emacs
```

`xwHasFocus()` is true only when `document.activeElement.nodeName` is `INPUT` or
`TEXTAREA`. ghostty-web renders to a `<canvas>` but keeps a 1×1 transparent
helper `<textarea>` for input, so **keeping that textarea focused is what makes
typing work at all inside Emacs** — and it's better than the GTK path, since the
terminal gets the raw keyboard with no round trip through Emacs.

Two traps this code works around:

1. `term.focus()` focuses the **container div**, not the textarea — and does it
   twice, once synchronously and again from a `setTimeout(…, 0)`:

   ```js
   focus() { this.element.focus(); setTimeout(() => this.element?.focus(), 0) }
   ```

   So any textarea focus you set synchronously gets yanked back on the next
   macrotask. Chrome doesn't care (keydown bubbles up from the container), but
   Emacs on macOS would send every keystroke to Emacs instead. `app.js` never
   calls `term.focus()`; it focuses the textarea itself and runs a `focusin`
   watchdog that redirects any focus landing inside the terminal back to the
   textarea.

2. Focus does not stick while the document is hidden, and an xwidget is often
   created before Emacs displays it. `app.js` re-asserts focus on
   `visibilitychange` and for ~1s after load.

### The keyboard model

One rule:

> **Every key goes to the terminal, except the handoff chords (`C-w`,
> `C-Escape`), which give the keyboard to Emacs.**

No modes, nothing to toggle. While the terminal has the keyboard it has *all* of
it — `C-x`, `C-c`, `ESC`, arrows — which is what makes it a real terminal, and why
Emacs bindings in that buffer do not fire. A handoff chord transfers the keyboard
to Emacs, after which Emacs behaves completely normally. Clicking the terminal
takes it back.

An earlier version had a second "passthrough" mode where Emacs held the keyboard
and forwarded keys. It worked, but two overlapping models meant you could land in
a state where neither Emacs nor the terminal appeared to respond. It is gone.

## Commands

| Command | Binding | Purpose |
| --- | --- | --- |
| `ghostty-web-term` | — | Open (or reuse) a terminal buffer; `C-u` forces a new one |
| `ghostty-web-term-zoom-in` / `-out` / `-reset` | `s-=` / `s--` / `s-0`, `=` / `-` | Scale the terminal font (also remaps `text-scale-*` and `xwidget-webkit-zoom-*`) |
| `ghostty-web-term-zoom-native-reset` | — | Undo WebKit view magnification, if the Zoom menu or a reload left some |
| `ghostty-web-term-focus` | `C-c C-f` | Give the keyboard back to the terminal (really works with the [focus module](#getting-back-into-the-terminal-without-clicking)) |
| `ghostty-web-term-autofocus-mode` | — | Keyboard follows window selection into the terminal |
| `ghostty-web-term-focus-state` | — | Report which view holds the keyboard |
| `ghostty-web-term-paste` | `s-v`, `C-c C-y` | Paste the clipboard into the shell |
| `ghostty-web-term-copy` | `s-c`, `C-c M-w` | Copy the terminal selection to the kill ring |
| `ghostty-web-term-blur` | `s-e`, `C-c C-k` | Hand the keyboard to Emacs from the Emacs side |
| `ghostty-web-term-send-region` | — | Send the region to the shell |
| `ghostty-web-term-send-line` | — | Send the current line |
| `ghostty-web-term-cd` | — | `cd` the shell to a directory |
| `ghostty-web-term-select` | `s-t`, `C-c C-o` | Select the terminal's window (fixes selection drift) |
| `ghostty-web-term-state` | `C-c C-s` | Report size/focus/connection |
| `ghostty-web-term-fit` | `C-c C-w` | Refit the grid to the widget |
| `ghostty-web-term-restart-server` | `C-c C-r` | Restart **this** terminal's PTY server and reload its page (asks first — it kills the shell) |
| `ghostty-web-term-stop-server` | — | Stop this terminal's PTY server |
| `ghostty-web-term-start-server` | — | Start this terminal's server again after it died |

**All of these bindings, super-key included, only fire while Emacs holds the
keyboard.** An earlier guess here — that macOS routes Cmd chords to Emacs
regardless — is wrong: once you click the widget it becomes first responder and
Cmd chords go to WebKit instead, so `s-v` silently stops working. That is the
whole explanation for "paste works until I click into the terminal, then it
doesn't". Paste after clicking is handled in the page instead (see Copy and
paste), not by these bindings.

### Getting back to Emacs

Press **`C-w`** (or `Ctrl-Escape`, or `C-g`). The shell never sees the chord.
Afterwards Emacs behaves completely normally — prefix keys, ESC-as-meta, `C-w h`,
`C-x o`, everything.

**To get back into the terminal: click it, or install the focus module** (see
[Getting back into the terminal without clicking](#getting-back-into-the-terminal-without-clicking)).
No *elisp* command can do it, and that is a hard limitation rather than an
oversight: `nsxwidget.m` contains exactly two `makeFirstResponder` calls and both
hand off *to* Emacs, `src/nsxwidget.h` exports no focus function at all, and
`xwidget-perform-lispy-event` is entirely inside `#ifdef USE_GTK`. Nothing gives
an xwidget the keyboard except WKWebView's own `mouseDown:` — from Lisp. From a
dynamic module, which runs in Emacs's process, that AppKit call is available.

Since `C-w` is consumed by the handoff, an evil window command is two presses:
`C-w` to leave the terminal, then your usual `C-w h`.

### Getting back into the terminal without clicking

`module/gw-focus.m` is a ~200-line dynamic module that makes the one AppKit call
the NS port never makes: `[[view window] makeFirstResponder:view]` on Emacs's own
`XwWebView`. It runs **in Emacs's process on Emacs's main thread**, so this is a
direct call, not a synthesized click, not Accessibility, and not a private API.
It lands in exactly the state a real click lands in — a state the existing C code
already knows how to leave, since the page hands the keyboard back by posting
`C-g`.

The target view is identified deterministically, not by coordinates: the module
walks `NSApp.windows` for `XwWebView` instances (`_OBJC_CLASS_$_XwWebView` is an
exported symbol, so `NSClassFromString` resolves in process) and matches the one
whose page URL contains `client=N&` — the id this package already puts in every
terminal's URL.

```elisp
(ghostty-web-term-autofocus-mode 1)   ; the keyboard follows window selection
```

With the mode on, selecting the terminal's window means you can type in it. Two
conditions must hold for a keystroke to reach the shell, and the mode satisfies
both: `firstResponder == XwWebView` (the module) and `document.activeElement` is
the helper `TEXTAREA` (`gw.focus()` in the page). That pair is exactly what
`nsxwidget.m`'s injected `xwHasFocus()` tests before calling `[super keyDown:]`.

**Know the trade before turning it on.** Any command that selects the terminal's
window now also takes the keyboard from Emacs — `other-window` into it, a jump,
`winner-undo`, some package calling `pop-to-buffer` — and a handoff chord is the
only way back. That is the feature and its hazard in one sentence. Prompts,
keyboard macros and isearch are excluded; ordinary window motion is not. Buffers
without `ghostty-web-term-mode` are never touched, so other xwidget buffers
(markdown previews, `+lookup` docs) keep behaving normally.

| Command | Purpose |
| --- | --- |
| `ghostty-web-term-focus` (`C-c C-f`) | Take the keyboard now; actually works with the module |
| `ghostty-web-term-release-keyboard` | Give it back from Emacs's side, when the page cannot post `C-g` |
| `ghostty-web-term-focus-state` | Name the window's first responder — the half of focus no Lisp can see |
| `ghostty-web-term-build-focus-module` | Recompile `gw-focus.dylib` |

The module is **compiled on demand** (one `clang` call, well under a second) and
**loaded lazily**, the first time the keyboard needs to move — Emacs modules
cannot be unloaded, so it is not loaded at startup. Everything fails soft: with
no module, or on a non-NS build, the terminal behaves exactly as it did before
and you click. Build it by hand with `cd module && make`.

Two caveats worth knowing:

- Loading an unsigned module needs an Emacs without library validation. Verified
  fine on `emacs-plus@30` (ad-hoc signed, no hardened runtime); the official
  GNU `Emacs.app` may refuse it.
- The only Emacs internal this depends on is the `XwWebView` class *name*. If a
  future build renames it, `gw-focus-take` returns nil and you are back to
  clicking — it does not crash.

The clean long-term fix is upstream: `nsxwidget.m` gaining a
`nsxwidget_focus_view` and a Lisp primitive to call it, which would delete this
module entirely.

#### If a window motion says "No window left of selected window"

That means the handoff worked — Emacs ran the motion — but from the wrong window.
A handoff transfers the *keyboard*; it does not change which window Emacs has
**selected**. Those are independent, and selection can drift while the terminal
holds the keyboard (a preview buffer popping up is enough). The motion then runs
from wherever selection actually is.

`ghostty-web-term-focus` now selects the terminal's window as well, which keeps
the invariant "terminal owns the keyboard ⟹ terminal's window is selected". If it
drifts anyway, `s-t` / `C-c C-o` (`ghostty-web-term-select`) puts selection back.

To check rather than guess:

```elisp
(mapcar (lambda (w) (list (buffer-name (window-buffer w))
                          (window-edges w)
                          (eq w (selected-window))))
        (window-list nil 'no-minibuf))
```

#### Why blurring alone was broken

The first version only blurred the helper textarea, which sets
`document.activeElement` but leaves the WKWebView as the window's **first
responder**. `nsxwidget.m` therefore keeps receiving every `keyDown:` and relays
it to the Emacs view from inside an asynchronous `evaluateJavaScript` completion
handler — one JS round trip per keystroke, delivered out of band. Single
self-inserting keys mostly survive that. Prefix sequences do not, which is
exactly the "I can't escape or switch windows" symptom.

The only thing that genuinely transfers the keyboard is
`makeFirstResponder:emacswindow`. A page can trigger it in exactly one way: post
`"C-g"` to the script message handler Emacs registers on every xwidget:

```objc
if ([message.body isEqualToString:@"C-g"])
  /* Just give up focus, no relay "C-g" to emacs … */
  [self.window makeFirstResponder:self.xw->xv->emacswindow];
```

Note its comment — it gives up focus *without* relaying anything, so the shell
sees nothing. `releaseKeyboard()` in `app.js` posts that message, which is why
`C-g` also works and why the handoff is now a real one.

### Zoom

Emacs text scaling cannot resize the terminal: zooming changes the font Emacs
draws with, but the widget's **pixel** size is unchanged, so the grid never
resizes. The equivalent operation is scaling the page's own font, which is what
`ghostty-web-term-zoom-in`/`-out`/`-reset` do before refitting the grid. The usual
zoom commands are remapped (`[remap text-scale-increase]` and friends), so
whatever keys you already use should work.

**`xwidget-webkit-zoom-in`/`-out` are remapped too**, which is what makes the
`-` / `+` / `=` keys of `xwidget-webkit-mode-map` resize the terminal. Left
alone they call into `xwidget.c`, which only bumps the WKWebView's
`magnification`. That is a scale applied to the rendered view, not a reflow: it
changes `devicePixelRatio` and `window.innerWidth` (2 → 2.6 and 738 → 567 for
three steps, measured) but leaves `documentElement.clientWidth` at 738. No
`ResizeObserver` fires, the grid stays at its old `cols`×`rows`, and you get a
stale grid drawn magnified and clipped — bigger text, same terminal, part of it
off the edge. This is why zoom appears to work on other xwidget pages and not
here: an HTML document reflows to the magnified viewport, a canvas terminal
sized from `clientWidth` cannot.

Nothing in Lisp can read the magnification back, so `ghostty-web-term-zoom-reset`
asks the page (`gw.magnification()`, `devicePixelRatio` over its value at load)
and unzooms by that much. `ghostty-web-term-zoom-native-reset` does only that
part. Worth having because the Zoom In/Out **menu and tool bar** items invoke
the command directly, where remapping does not apply, and magnification survives
a page reload.

Two smaller things the same feature needs:

- **The refit has to outlive the font change.** ghostty-web takes its cell size
  from the next render, so a `fit()` run synchronously after setting
  `term.options.fontSize` divides the widget by the *old* cell: 13px → 16px fit
  to 80×29 where 72×25 was correct, and the shell was told the wrong size. The
  page now fits again on the next animation frame and once more on a timer —
  the timer because rendering is `requestAnimationFrame`-driven and rAF does not
  fire while the widget is hidden.
- **Zoom is per terminal.** `ghostty-web-term-font-size` is made buffer-local by
  the mode, since each buffer drives its own page; the defcustom is the size new
  terminals open at. Shared, the counter would step the next terminal from
  another one's size.

Window *resizes* need no help — `xwidget.el` already registers
`xwidget-webkit-adjust-size-in-frame` on `window-size-change-functions`, and the
page's `ResizeObserver` refits from there. `ghostty-web-term-resync-size` forces
it if they ever drift.

### Copy and paste

Neither works natively inside an xwidget, and the reason is specific.
ghostty-web deliberately returns early on Cmd-V and Cmd-C:

```js
if ((A.ctrlKey || A.metaKey) && A.code === "KeyV" || A.metaKey && A.code === "KeyC") return;
```

It is declining to handle them so the *browser* performs a native copy/paste,
which then arrives as a `paste` event for `handlePaste`. In a browser that works.
In an Emacs xwidget that native paste event never happens — macOS routes Cmd-V
to Emacs's own menu key equivalent, and `nsxwidget.m` stubs out
`interpretKeyEvents:`.

Two paths cover the two keyboard owners:

- **Emacs holds the keyboard** — `s-v` runs `ghostty-web-term-paste`, which reads
  the clipboard and pushes it through `gw.input()`. `s-c`
  (`ghostty-web-term-copy`) reads `term.getSelection()` into the kill ring.
- **The widget holds the keyboard** (you clicked in) — Cmd-V never reaches Emacs,
  so the page handles it: a capture-phase listener reads
  `navigator.clipboard.readText()` directly. That API *does* work in this WebKit
  context (verified), which is what makes this possible. Multi-line pastes are wrapped in
bracketed-paste markers (`ghostty-web-term-bracketed-paste`) so a pasted
multi-line command does not execute line by line as it arrives.

### The scroll wheel sends arrow keys

This is a **ghostty-web bug**, not an Emacs one, and it is reproducible in Chrome.
`handleWheel` decides what to send purely from `isAlternateScreen()`:

```js
if (this.wasmTerm?.isAlternateScreen()) {
  const n = Math.min(Math.abs(Math.round(g.deltaY / 33)), 5);
  for (…) fire(dir === "up" ? "\x1B[A" : "\x1B[B");   // arrow keys
} else { …smoothScrollTo… }                            // viewport scroll
```

It never consults `hasMouseTracking()`. So an application that explicitly enabled
mouse reporting — vim with `mouse=a`, most TUIs — is sent Up/Down **keypresses**
instead of the mouse events it subscribed to. On the alternate screen it gets
arrows; on the normal screen it gets nothing at all, because the wheel is consumed
scrolling ghostty-web's own viewport. Either way the app never sees the wheel.

`app.js` replaces the handler via `attachCustomWheelEventHandler`:

| state | what is sent |
| --- | --- |
| mouse reporting on (`hasMouseTracking()`) | real wheel reports — SGR `ESC[<64/65;col;rowM` when mode 1006 is set, else legacy X10 |
| alternate screen, no mouse reporting | arrow keys, accumulated |
| normal screen, no mouse reporting | nothing — ghostty-web scrolls the scrollback |

Accumulation matters on macOS: ghostty-web caps steps per *event*, and a trackpad
flick delivers a burst of high-resolution momentum events, so one gesture could
fire dozens of arrows. We accumulate fractional lines and emit only whole steps,
so the count tracks the distance actually scrolled.

Verified in Chrome against `printf '\033[?1000h\033[?1006h'; cat -v`:

```
wheel down ×4 → ^[[<65;13;6M ^[[<65;13;6M ^[[<65;13;6M ^[[<65;13;6M
wheel up   ×4 → ^[[<64;13;6M ^[[<64;13;6M ^[[<64;13;6M ^[[<64;13;6M
```

with no arrow keys emitted. Tune with `ghostty-web-term-alt-screen-wheel`
(`"arrows"` / `"off"` / `"default"`) and `ghostty-web-term-wheel-sensitivity`;
those only affect the no-mouse-reporting case.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `ghostty-web-term-command` | `nil` | Shell command string; `nil` = interactive login shell |
| `ghostty-web-term-port` | `0` | `0` lets the OS pick — leave it there, see [Server lifetime](#server-lifetime) |
| `ghostty-web-term-font-size` | `13` | Font size in px |
| `ghostty-web-term-handoff-chords` | `"ctrl-w,ctrl-Escape"` | The only keys the terminal does not receive |
| `ghostty-web-term-alt-screen-wheel` | `"arrows"` | Wheel on the alternate screen: `arrows` / `off` / `default` |
| `ghostty-web-term-bracketed-paste` | `t` | Wrap multi-line pastes so they don't self-execute |
| `ghostty-web-term-directory-for-shell` | `nil` | Shell working directory; `nil` = `$HOME` |

### Server lifetime

**Every terminal buffer runs its own server process.** Opening a terminal spawns
a node process and waits for its readiness handshake (about a second); killing
the buffer deletes that process from the mode's `kill-buffer-hook`. Nothing is
shared, so nothing has to be counted: the server cannot outlive its buffer and
cannot be stopped out from under another terminal.

That is deliberately not the cheapest arrangement. One server can serve every
terminal — the Node side already spawns a PTY per WebSocket connection — and a
warm shared server opens the next terminal instantly instead of paying for a node
boot. What it cannot do is own its own lifetime. Nothing owned that process, so it
had to be reference-counted against the live terminal buffers, and the hook meant
to stop it when the last terminal died could not apply to terminals that were
already open: the mode body had already run in them. The price of correctness here
is ~40–60MB and ~1s per terminal, which is nothing at the two or three terminals
anyone actually keeps open.

Consequences worth knowing:

- **Leave `ghostty-web-term-port` at `0`.** A fixed port can only be bound once,
  so the second terminal's server exits at startup with `EADDRINUSE` (reported as
  "server exited during startup", with the details in its log buffer).
- Each server logs to its own buffer, `*ghostty-web-server-N*` — several node
  processes sharing one buffer would interleave into noise.
- `ghostty-web-term-restart-server` (`C-c C-r`) affects only the current
  terminal, and reloads its page: the new server has a new port and token, which
  live in the URL. It asks first, because that kills the shell.
- The control channel is the exception, and stays one listener for all pages: it
  multiplexes by client id and is not owned by any buffer. `M-x
  ghostty-web-term-control-stop` shuts it down; the next terminal brings it back
  on a new port with a new token.

### Sessions that survive reloads

An xwidget reload destroys a raw PTY and your shell with it. Point the server at
a multiplexer and the session outlives both reloads and Emacs restarts, and you
can attach the same session from real Ghostty with
`tmux attach -t emacs`:

```elisp
(setq ghostty-web-term-command "tmux new-session -A -s emacs")
```

## Security

Anything that can reach the server's port gets a shell, so:

- it binds `127.0.0.1` only;
- every `/ws` upgrade requires a random per-launch 48-char token, compared with
  `crypto.timingSafeEqual`;
- cross-origin upgrades are rejected;
- static paths are confined to `server/public`.

The server also strips `INSIDE_EMACS`, `EMACS`, `COLUMNS`, `LINES` and `TERMCAP`
from the child environment — otherwise a server started by Emacs hands the shell
an inherited environment that makes programs misdetect their terminal.

## Vendoring

`server/public/vendor/ghostty-web.js` is ghostty-web 0.4.0's ESM build, taken
from npm. It **inlines the 423KB WASM as a base64 `data:` URL**, so it is fully
self-contained — no CDN and no separate `.wasm` fetch. `ghostty-vt.wasm` is
copied alongside only as a fallback.

Building ghostty-web from source needs Zig and Bun; using the npm build avoids
both.

## Known rough edges

- **NS xwidget stability is the main risk**, not ghostty-web. Expect redraw
  glitches on window-configuration changes, clipping oddities, and possible
  crashes. Keep the terminal in its own window or frame.
- Rendering is driven by `requestAnimationFrame`, which is paused while the
  widget is hidden. Content is correct on return, but a hidden widget does not
  repaint.
- Box-drawing/shade glyphs (`▓▒░`) render imperfectly.
- Canvas rendering on retina may need a `fontSize` tweak to look crisp.
