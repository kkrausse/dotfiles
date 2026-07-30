// ghostty-web terminal client.
//
// Keyboard model, deliberately as simple as it can be:
//
//   EVERY key goes to the terminal, except a short list of handoff chords
//   (C-w, C-Escape) which give the keyboard to Emacs.
//
// There are no modes to be in and nothing to toggle. While the terminal has the
// keyboard it has all of it -- C-x, C-c, ESC, arrows -- which is what makes it a
// real terminal. A handoff chord transfers the keyboard to Emacs, after which
// Emacs behaves completely normally. Clicking the terminal takes it back.
//
// Two macOS details this depends on (see src/nsxwidget.m):
//
// 1. The embedded WKWebView decides where a keystroke goes by evaluating
//    `xwHasFocus()`, true only when `document.activeElement.nodeName` is INPUT or
//    TEXTAREA. ghostty-web renders to a <canvas> but keeps a helper <textarea>,
//    so keeping that textarea focused is what makes typing work at all.
//
// 2. Handing the keyboard back requires `makeFirstResponder:emacswindow`. Merely
//    blurring the textarea does NOT do it -- the WebView stays first responder
//    and relays keys through an async completion handler, which breaks prefix
//    sequences. See releaseKeyboard.

import { init, Terminal, FitAddon } from './vendor/ghostty-web.js';

const statusEl = document.getElementById('status');
const termEl = document.getElementById('terminal');

function setStatus(state, text) {
  statusEl.dataset.state = state;
  if (text !== undefined) statusEl.textContent = text;
}

/**
 * Show a message, then go back to whatever the connection state was.
 *
 * The status bar is hidden while connected, so a plain `setStatus('error', …)` for
 * a transient problem would stay on screen forever.
 */
let statusRevertTimer = null;
function flashStatus(text, ms = 4000) {
  setStatus('error', text);
  if (statusRevertTimer) clearTimeout(statusRevertTimer);
  statusRevertTimer = setTimeout(() => {
    statusRevertTimer = null;
    const connected = !!ws && ws.readyState === WebSocket.OPEN;
    if (connected) setStatus('connected', 'connected');
  }, ms);
}

const params = new URLSearchParams(location.search);
const token = params.get('token') || '';
const fontSize = Number(params.get('fontSize')) || 13;
const fontFamily =
  params.get('fontFamily') ||
  'ui-monospace, SFMono-Regular, Menlo, "JetBrains Mono", monospace';

// The entire special-cased key list. Everything else reaches the shell.
const handoffChords = (params.get('handoffChords') || 'ctrl-w,ctrl-Escape')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

// Wheel behavior on the alternate screen when the app has NOT enabled mouse
// reporting: 'arrows' emits accumulated arrow keys, 'off' ignores the wheel,
// 'default' restores ghostty-web's own burst-prone translation.
const wheelAltScreen = params.get('wheelAltScreen') || 'arrows';
const wheelSensitivity = Number(params.get('wheelSensitivity')) || 1;
const wheelMaxLines = Number(params.get('wheelMaxLines')) || 6;

// Identifies this page to the Emacs side, so a paste request is answered by the
// buffer that asked. Set by `ghostty-web-term--url'.
const clientId = params.get('client') || '';

// True when running inside an Emacs xwidget rather than a plain browser. Emacs
// registers this script message handler; a normal browser has no `window.webkit'.
const inEmacs = !!(window.webkit && window.webkit.messageHandlers);

// Emacs's control-plane WebSocket. Emacs hosts this itself, so the page can talk
// back to Emacs directly instead of routing control traffic through the PTY
// server's stdout.
const ctrlPort = params.get('ctrlPort') || '';
const ctrlToken = params.get('ctrlToken') || '';
let ctrl = null;
let ctrlAttempt = 0;

const theme = {
  background: '#1a1b26',
  foreground: '#a9b1d6',
  cursor: '#c0caf5',
  selectionBackground: '#33467c',
  black: '#15161e',
  red: '#f7768e',
  green: '#9ece6a',
  yellow: '#e0af68',
  blue: '#7aa2f7',
  magenta: '#bb9af7',
  cyan: '#7dcfff',
  white: '#a9b1d6',
  brightBlack: '#414868',
  brightRed: '#f7768e',
  brightGreen: '#9ece6a',
  brightYellow: '#e0af68',
  brightBlue: '#7aa2f7',
  brightMagenta: '#bb9af7',
  brightCyan: '#7dcfff',
  brightWhite: '#c0caf5',
};

let term;
let fit;
let ws;
let reconnectAttempt = 0;
let disposed = false;

/**
 * The helper textarea. `Terminal.textarea` is declared in the typings but is not
 * reliably populated in ghostty-web 0.4.0, so fall back to the DOM.
 */
function textareaEl() {
  return (term && term.textarea) || termEl.querySelector('textarea');
}

// Whether the terminal should own the keyboard. Cleared by a handoff so the
// watchdog below does not immediately grab focus back.
let wantKeyboard = true;

/**
 * Focus the helper textarea, not the container.
 *
 * Deliberately does NOT call `term.focus()`: in ghostty-web 0.4.0 that focuses
 * the *container* div, both synchronously and again from a setTimeout(…, 0), so
 * any textarea focus set synchronously gets yanked back on the next macrotask.
 * Chrome tolerates a focused container (keydown bubbles up from it), but Emacs on
 * macOS only routes keys to WebKit when activeElement is an INPUT/TEXTAREA.
 */
function ensureFocus() {
  if (!term) return false;
  wantKeyboard = true;
  const ta = textareaEl();
  if (ta && document.activeElement !== ta) ta.focus({ preventScroll: true });
  return isFocused();
}

/**
 * Re-focus the textarea only if the terminal is *supposed* to have the keyboard.
 *
 * The difference from `ensureFocus` matters. This runs from window-focus,
 * visibilitychange and the startup retries -- events that also fire when the user
 * merely switches back to Emacs. Calling `ensureFocus` there would set
 * `wantKeyboard` and silently undo a deliberate handoff, so after C-w, leaving
 * Emacs and coming back would hand the shell your keystrokes again.
 */
function reassertFocus() {
  if (!wantKeyboard) return false;
  return ensureFocus();
}

function isFocused() {
  const ta = textareaEl();
  return !!ta && document.activeElement === ta;
}

function reflectFocus() {
  termEl.dataset.focused = String(isFocused());
}

/**
 * Redirect any focus that lands inside the terminal to the textarea, so the
 * keyboard keeps working no matter which element ghostty-web focuses.
 */
function installFocusWatchdog() {
  document.addEventListener(
    'focusin',
    (ev) => {
      if (!wantKeyboard) return;
      const ta = textareaEl();
      if (!ta || ev.target === ta) return;
      if (ev.target === termEl || termEl.contains(ev.target)) {
        ta.focus({ preventScroll: true });
      }
    },
    true
  );
}

/**
 * Give the keyboard to Emacs, for real.
 *
 * Blurring the textarea is not sufficient: the WKWebView stays the window's first
 * responder and `nsxwidget.m` keeps receiving every keyDown, relaying it to Emacs
 * from inside an asynchronous `evaluateJavaScript` completion handler. Single keys
 * mostly survive that; prefix sequences (C-w h, C-x o, ESC-as-meta) do not.
 *
 * Only `makeFirstResponder:emacswindow` genuinely transfers the keyboard, and a
 * page can trigger it in exactly one way: post "C-g" to the script message handler
 * Emacs registers. Its own comment notes this gives up focus without relaying C-g
 * anywhere, so the shell sees nothing.
 */
function releaseKeyboard(chord) {
  wantKeyboard = false;
  // Report the chord before giving up first responder, so Emacs can feed the key
  // to its own command loop: otherwise C-w only hands off and you have to press
  // it a second time to start Emacs's C-w prefix.
  if (chord) controlSend({ type: 'handoff', chord, client: clientId });
  const ta = textareaEl();
  if (ta) ta.blur();
  if (document.body) document.body.focus?.();
  reflectFocus();
  try {
    window.webkit.messageHandlers.keyDown.postMessage('C-g');
    return true;
  } catch {
    // Not inside an Emacs xwidget (plain Chrome): blur is all there is, and it
    // is enough there.
    return false;
  }
}

function matchesChord(ev, chord) {
  const parts = chord.split('-');
  const key = parts.pop();
  const need = new Set(parts.map((p) => p.toLowerCase()));
  if (need.has('ctrl') !== ev.ctrlKey) return false;
  if (need.has('alt') !== ev.altKey) return false;
  if (need.has('shift') !== ev.shiftKey) return false;
  if (need.has('meta') !== ev.metaKey) return false;
  return ev.key === key || (ev.key && ev.key.toLowerCase() === key.toLowerCase());
}

/** The whole keyboard policy: handoff chords are ours, everything else is the shell's. */
function installKeyPolicy() {
  window.addEventListener(
    'keydown',
    (ev) => {
      const hit = handoffChords.find((chord) => matchesChord(ev, chord));
      if (!hit) return;
      // Capture phase + stopPropagation so ghostty-web never sees it and the
      // shell gets no ^W word-erase on the way out.
      ev.preventDefault();
      ev.stopPropagation();
      releaseKeyboard(hit);
    },
    true
  );
}

function cellMetrics() {
  let width = 8;
  let height = 20;
  try {
    const m = term.renderer && term.renderer.getMetrics && term.renderer.getMetrics();
    if (m) {
      if (m.width) width = m.width;
      if (m.height) height = m.height;
    }
  } catch { /* fall back to the estimates */ }
  return { width, height };
}

function terminalMode(n) {
  try {
    return !!term.getMode(n);
  } catch {
    return false;
  }
}

function mouseTrackingOn() {
  try {
    return !!term.hasMouseTracking();
  } catch {
    return false;
  }
}

/** 1-based cell under the pointer, clamped to the grid. */
function eventCell(ev) {
  const canvas = termEl.querySelector('canvas');
  const rect = (canvas || termEl).getBoundingClientRect();
  const { width, height } = cellMetrics();
  const col = Math.floor((ev.clientX - rect.left) / width) + 1;
  const row = Math.floor((ev.clientY - rect.top) / height) + 1;
  return {
    col: Math.min(Math.max(col, 1), term.cols),
    row: Math.min(Math.max(row, 1), term.rows),
  };
}

/**
 * Encode a wheel click as a mouse report. Button 64 is wheel-up, 65 wheel-down.
 * Prefers SGR (mode 1006); the legacy X10 fallback cannot address positions past
 * 223 and so is only correct on small grids.
 */
function mouseWheelReport(up, ev) {
  const { col, row } = eventCell(ev);
  const button = up ? 64 : 65;
  if (terminalMode(1006)) return `\x1b[<${button};${col};${row}M`;
  return `\x1b[M${String.fromCharCode(32 + button, 32 + col, 32 + row)}`;
}

function wheelLines(ev) {
  const { height } = cellMetrics();
  if (ev.deltaMode === WheelEvent.DOM_DELTA_LINE) return ev.deltaY;
  if (ev.deltaMode === WheelEvent.DOM_DELTA_PAGE) return ev.deltaY * term.rows;
  return ev.deltaY / height;
}

/**
 * Take over wheel handling.
 *
 * ghostty-web's handler decides purely from `isAlternateScreen()` and translates
 * the wheel into arrow keys, never checking `hasMouseTracking()`. So an app that
 * explicitly enabled mouse reporting (vim with `mouse=a`, most TUIs) is sent
 * Up/Down keypresses instead of the mouse events it subscribed to -- and on the
 * normal screen it gets nothing at all. Either way it never sees the wheel.
 *
 *   mouse reporting on   -> real wheel reports (what the app asked for)
 *   alt screen, no mouse -> arrow keys, accumulated so trackpad momentum cannot
 *                           spray dozens per gesture
 *   normal screen        -> defer to ghostty-web, which scrolls the scrollback
 */
function installWheelPolicy() {
  if (typeof term.attachCustomWheelEventHandler !== 'function') return;

  let accum = 0;
  term.attachCustomWheelEventHandler((ev) => {
    if (ev.deltaY === 0) return true;

    const tracking = mouseTrackingOn();
    if (!tracking) {
      const alt = !!(term.wasmTerm && term.wasmTerm.isAlternateScreen());
      if (!alt) return false; // normal screen: ghostty-web scrolls the viewport
      if (wheelAltScreen === 'off') return true;
      if (wheelAltScreen === 'default') return false;
    }

    accum += wheelLines(ev) * wheelSensitivity;
    let steps = Math.trunc(accum);
    if (steps === 0) return true;
    accum -= steps;
    const up = steps < 0;
    steps = Math.min(Math.abs(steps), wheelMaxLines);

    sendInput(
      tracking
        ? mouseWheelReport(up, ev).repeat(steps)
        : (up ? '\x1b[A' : '\x1b[B').repeat(steps)
    );
    return true;
  });
}

/**
 * Ask Emacs to paste the clipboard into this terminal.
 *
 * The page cannot read the clipboard itself: inside an Emacs xwidget
 * `navigator.clipboard.readText()' rejects with NotAllowedError, and
 * `document.execCommand("paste")' only "succeeds" by making WebKit show a native
 * Paste bubble that has to be clicked every single time.
 *
 * Rather than cache the clipboard on this side -- which goes stale the moment
 * something copies without Emacs noticing, exactly what breaks dictation and
 * clipboard-manager tools that copy and immediately press Cmd-V -- the request is
 * forwarded to Emacs, which reads the clipboard at this instant and calls
 * `gw.paste'. The trip is page -> PTY server -> its stdout -> the Emacs process
 * filter, all on the loopback socket that is already open.
 */
/**
 * Open the control channel to Emacs.
 *
 * Only small, occasional control messages travel here -- paste requests, handoff
 * notifications, debug taps. The terminal's own byte stream stays on the PTY
 * socket, because putting Emacs's Lisp-level WebSocket framing in the path of
 * every chunk of shell output would cost throughput for no benefit.
 */
function openControlChannel() {
  if (!inEmacs || !ctrlPort || !ctrlToken) return;
  try {
    ctrl = new WebSocket(`ws://127.0.0.1:${ctrlPort}/?token=${encodeURIComponent(ctrlToken)}`);
  } catch {
    ctrl = null;
    return;
  }
  ctrl.onopen = () => {
    ctrlAttempt = 0;
    ctrl.send(JSON.stringify({ type: 'hello', client: clientId }));
  };
  ctrl.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch { return; }
    if (msg.type === 'paste') {
      // Emacs read the clipboard just now, so this is never stale.
      if (msg.bracket === false) sendInput(String(msg.data));
      else pasteText(String(msg.data));
    } else if (msg.type === 'paste-empty') {
      flashStatus('nothing to paste — the clipboard is empty');
    } else if (msg.type === 'ping-state') {
      controlSend({ type: 'log', text: JSON.stringify(window.gw.state()) });
    }
  };
  ctrl.onclose = () => {
    ctrl = null;
    if (disposed || ctrlAttempt > 5) return;
    ctrlAttempt += 1;
    setTimeout(openControlChannel, Math.min(2000, 200 * 2 ** (ctrlAttempt - 1)));
  };
  ctrl.onerror = () => { /* onclose retries */ };
}

function controlSend(obj) {
  if (!ctrl || ctrl.readyState !== WebSocket.OPEN) return false;
  ctrl.send(JSON.stringify(obj));
  return true;
}

function requestPasteFromEmacs() {
  // Control channel first. The PTY-relay path is kept as a fallback so paste
  // still works if the control socket is down for any reason.
  if (controlSend({ type: 'paste-request', client: clientId })) return true;
  if (!ws || ws.readyState !== WebSocket.OPEN) return false;
  ws.send(JSON.stringify({ type: 'paste-request' }));
  return true;
}

function pasteText(text) {
  if (!text) return 0;
  const bracketed = terminalMode(2004) && text.includes('\n');
  sendInput(bracketed ? `\x1b[200~${text}\x1b[201~` : text);
  return text.length;
}

/**
 * Make Cmd-V work.
 *
 * ghostty-web returns early on Cmd-V expecting the browser to perform a native
 * paste that arrives as a `paste` event; inside an xwidget that never happens, so
 * by default nothing is pasted at all.
 *
 * Inside Emacs the key is turned into a paste request that Emacs answers with the
 * current clipboard (see requestPasteFromEmacs); in a plain browser the Clipboard
 * API is used directly. A failure is reported in the status line instead of being
 * swallowed, because a paste that silently does nothing is indistinguishable from
 * a broken terminal.
 */
function installPastePolicy() {
  // If WebKit ever does deliver a native paste, take it -- clipboardData needs no
  // permission and never prompts.
  window.addEventListener(
    'paste',
    (ev) => {
      const data = ev.clipboardData && ev.clipboardData.getData('text/plain');
      if (!data) return;
      ev.preventDefault();
      ev.stopPropagation();
      pasteText(data);
    },
    true
  );

  window.addEventListener(
    'keydown',
    (ev) => {
      const isPaste = ev.code === 'KeyV' && (ev.metaKey || (ev.ctrlKey && ev.shiftKey));
      if (!isPaste) return;
      ev.preventDefault();
      ev.stopPropagation();

      if (inEmacs) {
        if (!requestPasteFromEmacs()) flashStatus('not connected — cannot paste');
        return;
      }

      // Plain browser: the Clipboard API actually works here.
      if (!navigator.clipboard || !navigator.clipboard.readText) {
        flashStatus('this browser will not allow reading the clipboard');
        return;
      }
      navigator.clipboard
        .readText()
        .then((text) => { if (text) pasteText(text); })
        .catch((err) => flashStatus(`clipboard read denied (${err && err.name})`));
    },
    true
  );
}

function wsUrl() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const u = new URL(`${proto}//${location.host}/ws`);
  u.searchParams.set('token', token);
  u.searchParams.set('client', clientId);
  u.searchParams.set('cols', String(term?.cols ?? 80));
  u.searchParams.set('rows', String(term?.rows ?? 24));
  return u.toString();
}

function sendResize(cols, rows) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'resize', cols, rows }));
  }
}

function sendInput(data) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'input', data }));
  }
}

function connect() {
  if (disposed) return;
  setStatus('boot', reconnectAttempt ? `reconnecting (attempt ${reconnectAttempt})…` : 'connecting…');

  ws = new WebSocket(wsUrl());
  ws.binaryType = 'arraybuffer';

  ws.onopen = () => {
    reconnectAttempt = 0;
    setStatus('connected', 'connected');
    sendResize(term.cols, term.rows);
    ensureFocus();
    reflectFocus();
  };

  ws.onmessage = (ev) => {
    if (typeof ev.data === 'string') term.write(ev.data);
    else term.write(new Uint8Array(ev.data));
  };

  ws.onclose = (ev) => {
    if (disposed) return;
    if (ev.code === 1000) {
      // Clean close means the shell exited. Reconnecting would silently spawn a
      // new one and hide that, so stop and let the user decide.
      setStatus('error', 'shell exited. reload to start a new session.');
      return;
    }
    if (ev.code === 1006 && reconnectAttempt === 0 && !token) {
      setStatus('error', 'no token in URL — open the URL printed by the server.');
      return;
    }
    reconnectAttempt += 1;
    if (reconnectAttempt > 5) {
      setStatus('error', `disconnected (${ev.code}). reload to retry.`);
      return;
    }
    const delay = Math.min(2000, 200 * 2 ** (reconnectAttempt - 1));
    setStatus('boot', `disconnected (${ev.code}); retrying in ${delay}ms…`);
    setTimeout(connect, delay);
  };
}

async function main() {
  setStatus('boot', 'loading ghostty wasm…');
  try {
    // The vendored ESM bundle inlines the WASM as a data: URL, so this needs no
    // network fetch and no separate .wasm request.
    await init();
  } catch (err) {
    setStatus('error', `failed to load ghostty wasm: ${err.message}`);
    throw err;
  }

  term = new Terminal({
    fontSize,
    fontFamily,
    theme,
    cursorBlink: true,
    scrollback: 10000,
    allowTransparency: false,
  });

  fit = new FitAddon();
  term.loadAddon(fit);
  term.open(termEl);
  fit.fit();
  fit.observeResize();

  installKeyPolicy();
  installWheelPolicy();
  installPastePolicy();
  installFocusWatchdog();
  openControlChannel();

  term.onData(sendInput);
  term.onResize(({ cols, rows }) => sendResize(cols, rows));
  term.onTitleChange((t) => {
    window.gwTitle = t;
    document.title = t || 'ghostty terminal';
  });

  // Clicking takes the keyboard back; it is the only thing that can, since
  // nothing in nsxwidget.m gives an xwidget first responder except mouseDown.
  termEl.addEventListener('mousedown', () => setTimeout(ensureFocus, 0));
  window.addEventListener('focus', () => setTimeout(reassertFocus, 0));
  document.addEventListener('focusin', reflectFocus);
  document.addEventListener('focusout', () => setTimeout(reflectFocus, 0));

  connect();

  // Focus does not stick while the document is hidden, and an xwidget is often
  // created before Emacs displays it, so re-assert for a short window.
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) reassertFocus();
    reflectFocus();
  });
  for (const delay of [0, 50, 250, 1000]) {
    setTimeout(() => {
      if (!document.hidden && !isFocused()) reassertFocus();
      reflectFocus();
    }, delay);
  }
  reflectFocus();

  // Control surface for Emacs, driven via `xwidget-webkit-execute-script`.
  window.gw = {
    _term: term,
    focus: () => { const r = ensureFocus(); reflectFocus(); return r; },
    blur: () => releaseKeyboard(),
    isFocused,
    input: (data) => { sendInput(String(data)); return true; },
    // Unlike `input`, this applies bracketed paste when the application asked for
    // it, so Emacs does not have to guess at the terminal's DECSET 2004 state.
    paste: (data) => pasteText(String(data)),
    // How Emacs answers a paste request when there is nothing on the clipboard.
    // Without this the key would silently do nothing, which reads as breakage.
    notifyEmpty: () => { flashStatus('nothing to paste — the clipboard is empty'); return true; },
    getSelection: () => term.getSelection(),
    hasSelection: () => term.hasSelection(),
    clearSelection: () => { term.clearSelection(); return true; },
    selectAll: () => { term.selectAll(); return true; },
    fit: () => { fit.fit(); return { cols: term.cols, rows: term.rows }; },
    resize: (cols, rows) => { term.resize(cols, rows); sendResize(cols, rows); return true; },
    setFontSize: (px) => { term.options.fontSize = Number(px); fit.fit(); return term.options.fontSize; },
    clear: () => { term.clear(); return true; },
    title: () => window.gwTitle || '',
    mouseTracking: () => mouseTrackingOn(),
    mode: (n) => terminalMode(Number(n)),
    state: () => ({
      cols: term.cols,
      rows: term.rows,
      focused: isFocused(),
      connected: !!ws && ws.readyState === WebSocket.OPEN,
      title: window.gwTitle || '',
      status: statusEl.dataset.state,
    }),
  };
  window.gwReady = true;
}

main().catch((err) => {
  console.error('[ghostty-web-emacs]', err);
});
