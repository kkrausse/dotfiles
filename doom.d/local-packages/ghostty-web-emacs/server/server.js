#!/usr/bin/env node
// Loopback static + PTY WebSocket server backing the ghostty-web Emacs terminal.
//
// Serves public/ over HTTP on 127.0.0.1 and exposes a PTY per WebSocket
// connection at /ws. Every /ws connection requires the session token that this
// process prints on startup, because anything able to reach this port gets a
// real shell.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import * as pty from 'node-pty';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC = path.join(HERE, 'public');

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) out[key] = true;
    else { out[key] = next; i++; }
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const HOST = args.host || '127.0.0.1';
const PORT = Number(args.port || process.env.GHOSTTY_WEB_PORT || 0);
const CWD = args.cwd || process.env.HOME || os.homedir();
// --cmd is a shell command string run by the login shell, so `--cmd "tmux
// new-session -A -s emacs"` works. With no --cmd we exec an interactive login
// shell directly.
const CMD = args.cmd && args.cmd !== true ? String(args.cmd) : null;
const SHELL = args.shell || process.env.SHELL || '/bin/zsh';
const TERM = args.term || process.env.GHOSTTY_WEB_TERM || 'xterm-256color';
const TOKEN = process.env.GHOSTTY_WEB_TOKEN || crypto.randomBytes(24).toString('hex');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

function send(res, status, body, headers = {}) {
  res.writeHead(status, {
    'Cache-Control': 'no-store',
    // The page is only ever framed by itself; keep it from being embedded.
    'X-Content-Type-Options': 'nosniff',
    ...headers,
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    return send(res, 400, 'bad request');
  }
  if (pathname === '/') pathname = '/index.html';

  if (pathname === '/health') {
    return send(res, 200, JSON.stringify({ ok: true, pid: process.pid }), {
      'Content-Type': MIME['.json'],
    });
  }

  // Resolve inside PUBLIC only — no traversal out of the served root.
  const target = path.join(PUBLIC, path.normalize(pathname));
  if (!target.startsWith(PUBLIC + path.sep)) return send(res, 403, 'forbidden');

  fs.readFile(target, (err, buf) => {
    if (err) return send(res, 404, 'not found');
    send(res, 200, buf, {
      'Content-Type': MIME[path.extname(target)] || 'application/octet-stream',
    });
  });
});

const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (url.pathname !== '/ws') {
    socket.destroy();
    return;
  }

  // Token gate. Compared in constant time to avoid leaking it byte-by-byte.
  const supplied = Buffer.from(url.searchParams.get('token') || '');
  const expected = Buffer.from(TOKEN);
  const ok =
    supplied.length === expected.length && crypto.timingSafeEqual(supplied, expected);
  if (!ok) {
    socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
    socket.destroy();
    return;
  }

  // Reject cross-origin upgrades. A missing Origin is allowed: some embedded
  // WebKit contexts omit it, and the token is the real gate.
  const origin = req.headers.origin;
  if (origin) {
    let host;
    try { host = new URL(origin).hostname; } catch { host = null; }
    if (host !== '127.0.0.1' && host !== 'localhost' && host !== '[::1]') {
      socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
      socket.destroy();
      return;
    }
  }

  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req, url);
  });
});

let sessions = 0;

wss.on('connection', (ws, req, url) => {
  const cols = Math.max(2, Number(url.searchParams.get('cols')) || 80);
  const rows = Math.max(2, Number(url.searchParams.get('rows')) || 24);
  // Identifies which Emacs terminal buffer this connection belongs to, so a
  // paste request can be answered by the right one when several are open.
  const client = url.searchParams.get('client') || '';

  // Emacs exports variables that change how child programs behave. If this
  // server was started by Emacs the shell would inherit them and misdetect its
  // terminal, so strip them before spawning.
  const env = { ...process.env };
  for (const k of ['INSIDE_EMACS', 'EMACS', 'COLUMNS', 'LINES', 'TERMCAP']) delete env[k];
  env.TERM = TERM;
  env.COLORTERM = 'truecolor';
  env.TERM_PROGRAM = 'ghostty-web';
  delete env.GHOSTTY_WEB_TOKEN;

  const file = CMD ? SHELL : SHELL;
  const argv = CMD ? ['-l', '-c', CMD] : ['-l'];

  let child;
  try {
    child = pty.spawn(file, argv, {
      name: TERM,
      cols,
      rows,
      cwd: CWD,
      env,
      // Raw bytes: forwarding Buffers verbatim keeps output byte-exact instead
      // of round-tripping through a lossy string decode.
      encoding: null,
    });
  } catch (err) {
    ws.close(1011, `spawn failed: ${err.message}`);
    return;
  }

  const id = ++sessions;
  log(`session ${id} open  pid=${child.pid} ${cols}x${rows} cmd=${CMD || argv.join(' ')}`);

  child.onData((data) => {
    if (ws.readyState !== ws.OPEN) return;
    ws.send(Buffer.isBuffer(data) ? data : Buffer.from(String(data), 'utf8'));
  });

  child.onExit(({ exitCode, signal }) => {
    log(`session ${id} pty exit code=${exitCode} signal=${signal ?? '-'}`);
    if (ws.readyState === ws.OPEN) ws.close(1000, 'pty exited');
  });

  ws.on('message', (raw, isBinary) => {
    if (isBinary) {
      child.write(raw);
      return;
    }
    let msg;
    try { msg = JSON.parse(raw.toString('utf8')); } catch { return; }
    if (msg.type === 'input' && typeof msg.data === 'string') {
      child.write(msg.data);
    } else if (msg.type === 'resize') {
      const c = Math.max(2, Number(msg.cols) || 0);
      const r = Math.max(2, Number(msg.rows) || 0);
      if (c && r) { try { child.resize(c, r); } catch { /* pty already gone */ } }
    } else if (msg.type === 'paste-request') {
      // WebKit will not let the page read the clipboard inside an Emacs xwidget,
      // so the page asks Emacs to do it. Relayed as a machine-readable stdout
      // line, which the Emacs process filter is already reading.  Emacs answers
      // by calling `gw.paste' with the clipboard as it is *now*, which is what
      // makes a paste-and-type tool (dictation, clipboard manager) work: nothing
      // is cached, so nothing can be stale.
      process.stdout.write(
        `GHOSTTY_WEB_PASTE_REQUEST ${JSON.stringify({ client, session: id })}\n`
      );
    }
  });

  const shutdown = () => {
    try { child.kill(); } catch { /* already dead */ }
  };
  ws.on('close', () => { log(`session ${id} ws close`); shutdown(); });
  ws.on('error', shutdown);
});

function log(msg) {
  process.stderr.write(`[ghostty-web-server] ${msg}\n`);
}

server.listen(PORT, HOST, () => {
  const { port } = server.address();
  const url = `http://${HOST}:${port}/?token=${TOKEN}`;
  // Machine-readable handshake line: the Emacs side blocks on this to learn the
  // negotiated port and token.
  process.stdout.write(
    `GHOSTTY_WEB_READY ${JSON.stringify({ url, port, host: HOST, token: TOKEN, pid: process.pid })}\n`
  );
  log(`listening on ${url}`);
});

for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(sig, () => {
    log(`got ${sig}, shutting down`);
    for (const ws of wss.clients) { try { ws.close(1001, 'server shutdown'); } catch {} }
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 500).unref();
  });
}
