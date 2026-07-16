# remote-kbm

Turn your phone into a wireless trackpad + keyboard for your desktop. No app install —
the desktop runs a tiny agent that serves a web page over your LAN; you open the printed
URL on your phone and control the machine.

## How it works

```
phone browser  ──WebSocket (JSON)──▶  desktop agent  ──pynput──▶  OS mouse/keyboard
```

One page (`client/index.html`) served by one agent (`server/`). Works on iPhone and Android
because it is just a web page over WiFi.

## Setup

Run the agent on the **native OS of the machine you want to control** — the same box, directly.

**Windows** (PowerShell):
```powershell
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python server\main.py
```

**macOS / Linux**:
```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server/main.py
```

The agent prints a **QR code** plus a URL like `http://192.168.1.23:8765/?k=XXXX`. Scan the QR
with your phone camera (or type the URL) — the phone must be on the **same WiFi**. The status
dot turns green when connected. The `?k=` token gates access so a random device on the network
can't drive your machine. The token is saved to `~/.remote-kbm-token` so it survives agent
restarts (delete that file to rotate it).

**Install as an app:** open the page **via the QR link**, then use the browser menu →
*Add to Home Screen* (Android Chrome: *Install app*). It launches fullscreen with its own
icon and the token baked in — no rescanning. While you use it, the page keeps your phone
screen awake. If it ever shows *disconnected*, the status text says why (agent not running /
wrong WiFi / stale token) — tap it to retry; after rotating the token, remove and re-add the
app.

> **Do not run the agent inside WSL.** WSL2 uses a NAT network (its `172.x` IP is unreachable
> from your phone) *and* pynput there controls the WSLg Linux display, not the real Windows
> desktop. To control Windows, install Python on Windows and run it from PowerShell as above.

## Gestures

| Action | Result |
|---|---|
| One-finger drag | Move cursor |
| Tap | Left click |
| Two-finger tap | Right click |
| Two-finger drag | Scroll |
| Pinch | Zoom (Ctrl + wheel) |
| Double-tap then hold + drag | Click-and-drag |

Cursor speed is adaptive: move slowly for precision, flick fast to cross the whole screen.
Tune `GAIN_MIN` / `GAIN_MAX` / `ACCEL` at the top of the client script if it feels off.

Bottom buttons and the keyboard panel (⌨) cover clicks, special keys, and shortcuts. The panel
has four tabs: **Type** (text box + Esc/Tab/arrows/Enter/⌫/Del and latching Ctrl/Alt/Shift/Win
modifiers — latch one, then press a key), **Shortcuts** (Start, Alt-Tab, Copy/Paste/Cut,
Undo/Redo, All, Save, Find, Close, Show-desktop), **Media** (volume, play/pause/next/previous),
and **Fn** (F1–F12). The text box shows what you type and mirrors edits (including autocorrect)
to the PC; ✕ clears the box locally without sending anything.

## OS notes

- **Windows** — works out of the box.
- **macOS** — grant your terminal app *Accessibility* permission (System Settings → Privacy &
  Security → Accessibility), or pynput can't inject input.
- **Linux** — X11 works directly. Under Wayland, pynput needs access to `/dev/uinput`.
- **Firewall** — allow inbound TCP on port `8765` (first run may prompt).

## Layout

- `server/main.py` — aiohttp: serves the page, handles the WebSocket, checks the token.
- `server/inject.py` — maps protocol messages to pynput calls. Run it directly for a self-check:
  `.venv/bin/python server/inject.py`.
- `client/index.html` — the whole phone app (connection, trackpad, keyboard).
