# ghostty-web-emacs

A real shell inside an Emacs WebKit xwidget buffer, rendered by
[ghostty-web](https://github.com/coder/ghostty-web) — Ghostty's VT parser
compiled to WASM.

Two pieces:

- `server/` — a loopback Node server. Serves the page and gives each WebSocket
  connection its own PTY.
- `ghostty-web-term.el` — starts that server on demand and points an xwidget at
  it.

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
| `ghostty-web-term-zoom-in` / `-out` / `-reset` | `s-=` / `s--` / `s-0` | Scale the terminal font (also remaps `text-scale-*`) |
| `ghostty-web-term-focus` | `C-c C-f` | Give the keyboard back to the terminal |
| `ghostty-web-term-paste` | `s-v`, `C-c C-y` | Paste the clipboard into the shell |
| `ghostty-web-term-copy` | `s-c`, `C-c M-w` | Copy the terminal selection to the kill ring |
| `ghostty-web-term-blur` | `s-e`, `C-c C-k` | Hand the keyboard to Emacs from the Emacs side |
| `ghostty-web-term-send-region` | — | Send the region to the shell |
| `ghostty-web-term-send-line` | — | Send the current line |
| `ghostty-web-term-cd` | — | `cd` the shell to a directory |
| `ghostty-web-term-select` | `s-t`, `C-c C-o` | Select the terminal's window (fixes selection drift) |
| `ghostty-web-term-state` | `C-c C-s` | Report size/focus/connection |
| `ghostty-web-term-fit` | `C-c C-w` | Refit the grid to the widget |
| `ghostty-web-term-restart-server` | `C-c C-r` | Restart the PTY server |

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

**To get back into the terminal, click it.** That is a hard limitation, not an
oversight: `nsxwidget.m` contains exactly two `makeFirstResponder` calls and both
hand off *to* Emacs. Nothing gives an xwidget the keyboard back except
WKWebView's default `mouseDown:`, so no elisp command can do it.

Since `C-w` is consumed by the handoff, an evil window command is two presses:
`C-w` to leave the terminal, then your usual `C-w h`.

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
| `ghostty-web-term-port` | `0` | `0` lets the OS pick |
| `ghostty-web-term-font-size` | `13` | Font size in px |
| `ghostty-web-term-handoff-chords` | `"ctrl-w,ctrl-Escape"` | The only keys the terminal does not receive |
| `ghostty-web-term-alt-screen-wheel` | `"arrows"` | Wheel on the alternate screen: `arrows` / `off` / `default` |
| `ghostty-web-term-bracketed-paste` | `t` | Wrap multi-line pastes so they don't self-execute |
| `ghostty-web-term-directory-for-shell` | `nil` | Shell working directory; `nil` = `$HOME` |

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
