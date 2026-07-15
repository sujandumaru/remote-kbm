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

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python server/main.py
```

The agent prints a URL like `http://192.168.1.23:8765/?k=XXXX`. Open it on a phone that is on
the **same WiFi**. The status dot turns green when connected. The `?k=` token gates access so a
random device on the network can't drive your machine.

## Gestures

| Action | Result |
|---|---|
| One-finger drag | Move cursor |
| Tap | Left click |
| Two-finger tap | Right click |
| Two-finger drag | Scroll |
| Pinch | Zoom (Ctrl + wheel) |
| Double-tap then hold + drag | Click-and-drag |

Bottom buttons and the keyboard panel (⌨) cover clicks, special keys, and Ctrl/Alt/Shift/Cmd
combos (latch a modifier, then press a key).

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
