# remote-kbm

[![Cross-platform checks](https://github.com/sujandumaru/remote-kbm/actions/workflows/ci.yml/badge.svg)](https://github.com/sujandumaru/remote-kbm/actions/workflows/ci.yml)

Turn your phone into a wireless trackpad + keyboard for your desktop. No app install —
the desktop runs a tiny agent that serves a web page over your LAN; you open the printed
URL on your phone and control the machine.

## How it works

```
phone browser  ──WebSocket (JSON)──▶  desktop agent  ──pynput──▶  OS mouse/keyboard
```

One page (`client/index.html`) served by one agent (`server/`). Works on iPhone and Android
because it is just a web page over WiFi.

## Supported desktops

Input injection must run on the **native OS desktop being controlled**:

| Clone/runtime | Support | Startup mechanism |
|---|---|---|
| Windows | Full | Per-user Windows Scheduled Task |
| Clone stored in WSL, controlling Windows | Full through **Windows Python** | Runtime copied to Windows; per-user Windows task |
| macOS | Full after Accessibility approval | Per-user LaunchAgent |
| Linux with X11/Xorg | Full | Freedesktop graphical autostart |
| Linux with Wayland | Limited to Xwayland apps | Sign in with an Xorg/X11 session for full control |

Running Linux Python inside WSL is deliberately blocked: it would target WSLg, not the Windows
desktop, and WSL2 NAT may expose only a localhost relay. The WSL installer routes to Windows
Python automatically.

## Install and start automatically

Install Python 3.10 or newer first. Each installer creates an isolated environment in the user's
application-data directory, copies the small runtime there, installs the dependencies, registers
native per-user startup, and prints the QR code when the terminal supports it (the URL is always
printed). The clone can be moved or deleted after installation; rerun the installer after pulling
updates. No administrator account is required for the startup registration.

Startup happens when the user **signs in**, not before login, because desktop input injection
must run inside that user's graphical session.

### Windows clone

Open Windows PowerShell in the cloned repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install-startup.ps1
```

If `py --version` fails, install Python from the Microsoft Store or
[python.org](https://www.python.org/downloads/windows/). On the first server launch, allow Python
through Windows Firewall on **Private networks**.

### Clone stored inside WSL

Run this from the repository in WSL:

```bash
./install.sh
```

The dispatcher converts the repository path with `wslpath` and invokes the Windows installer.
It copies the runtime and Python environment to `%LOCALAPPDATA%\remote-kbm`, then registers a
Windows task. WSL does not need to be running at later sign-ins.

### macOS or native Linux

Run this from the cloned repository:

```bash
./install.sh
```

If the executable bit was lost when downloading a ZIP, use `sh ./install.sh`. On macOS, approve
the printed Python interpreter in **System Settings → Privacy & Security → Accessibility**. On
Linux, use an Xorg/X11 desktop session; `pynput` cannot control the full native Wayland desktop.

### Remove automatic startup

On macOS, Linux, or WSL:

```bash
./uninstall.sh
```

On Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\uninstall-startup.ps1
```

Uninstalling startup keeps the installed runtime, isolated environment, logs, and access token so
reinstalling is quick and existing phone icons keep working.

## Connect your phone

The installer and server print a **QR code** plus a URL like
`http://192.168.1.23:8765/?k=XXXX`. Scan the QR
with your phone camera (or type the URL) — the phone must be on the **same WiFi**. The status
dot turns green when connected. The `?k=` token gates access so a random device on the network
can't drive your machine. The token is saved to `~/.remote-kbm-token` (on Windows,
`C:\Users\<you>\.remote-kbm-token`) so it survives agent restarts — delete that file to rotate it.

**Install as an app:** open the page **via the QR link**, then use the browser menu →
*Add to Home Screen* (Android Chrome: *Install app*). It launches fullscreen with its own
icon and the token baked in — no rescanning. While you use it, the page keeps your phone
screen awake. If it ever shows *disconnected*, the status text says why (agent not running /
wrong WiFi / stale token) — tap it to retry; after rotating the token, remove and re-add the
app.

On iPhone, use Safari's **Share → Add to Home Screen**. On Android, use Chrome's
**⋮ → Install app** or **Add to Home screen**. After desktop sign-in, opening that icon reconnects
to the computer automatically.

The installed icon remembers the laptop's current LAN address. For a dependable permanent setup,
reserve the laptop's WiFi address in your router's DHCP settings. If the laptop's address changes,
scan the newly printed URL and remove/re-add the home-screen app.

## Security

The `?k=` URL is effectively a remote-control credential. Keep it private, use remote-kbm only on
a trusted LAN, and **do not** port-forward `8765` to the internet. Traffic is plain HTTP/WebSocket
because the intended boundary is the local network. To revoke installed phones, stop the agent,
delete `~/.remote-kbm-token`, rerun the installer, and install the newly printed phone URL.

## Gestures

| Action | Result |
|---|---|
| One-finger drag | Move cursor |
| Tap | Left click |
| Two-finger tap | Right click |
| Two-finger drag | Scroll |
| Pinch | Zoom (Ctrl + wheel) |
| Press and hold, then drag | Click-and-drag |

Cursor speed is adaptive: move slowly for precision, flick fast to cross the whole screen.
Everything about the feel is adjustable from the phone — see **SteadyTouch** below.

**Two ways to drag.** Press and hold one finger still on the pad; after `Hold time before drag`
the left button goes down — the pad shows a coloured border and the phone buzzes if it can — and
from then on your finger drags. Lift to let go. Aim the cursor first, lift, then press and hold.
Nothing is clicked before the button goes down, which matters on window borders: a click
immediately followed by a drag is a double-click to Windows, and double-clicking a border resizes
the window instead.

**Drag lock** needs no timing at all, which makes it the dependable option for long drags and for
small targets like window resize borders. Park the cursor, tap `Drag lock` (it latches, like the
Ctrl/Shift keys), drag on the pad — as many strokes as you need — then tap it again to let go.
Taps are ignored while it is latched, since a tap would release the button. A held button is
dropped if you background the app, and the agent drops it if the phone disconnects.

Bottom buttons and the keyboard panel (⌨) cover clicks, special keys, and shortcuts. The panel
has five tabs: **Type** (text box + Esc/Tab/arrows/Enter/⌫/Del and latching Ctrl/Alt/Shift/Win
modifiers — latch one, then press a key), **Shortcuts** (Start, Alt-Tab, Copy/Paste/Cut,
Undo/Redo, All, Save, Find, Close, Show-desktop), **Media** (volume, play/pause/next/previous),
**Fn** (F1–F12), and **Touch** (see below). The text box shows what you type and mirrors edits
(including autocorrect) to the PC; ✕ clears the box locally without sending anything.

The latching Ctrl/Alt/Shift/Win modifiers are **sticky keys**: you never hold two things at once,
so shortcuts stay reachable one finger at a time.

## SteadyTouch

For anyone whose hands do not match the defaults — tremor, limited range, one hand busy, or just
a phone that feels too twitchy. Everything is a phone-side setting; the desktop agent is unchanged.

Open ⌨ → **Touch**. Start with a preset, then adjust only what still bothers you.

| Preset | For |
|---|---|
| **Default** | The original feel, unchanged. Steadying off. |
| **Precision** | Slow, deliberate work. Low gain, light steadying, small dead zones. |
| **Accessibility** | Tremor and unsteady hands. Heavy steadying, forgiving taps, dwell click on. |

### Steadying (tremor filtering)

Slow movement is smoothed hard while fast movement passes straight through, so a flick keeps its
full speed and gains no lag. The cursor also remembers movement smaller than one pixel instead of
discarding it, so very slow drags still travel.

| Setting | What it does |
|---|---|
| `Steadiness` | Main knob. `1` = off. Lower = more damping of slow, shaky movement. |
| `Tremor dead zone` | Movement smaller than this is ignored completely. Raise it if the cursor creeps while your finger rests. |
| `Steadying starts below` | Finger speed under this is treated as shake. |
| `Full speed passes through` | Finger speed above this is never touched, so flicks stay instant. |

### Dwell click

Hold still and it clicks for you — no tap needed. Off unless you turn it on or pick
**Accessibility**. A ring fills to show progress and fires once; move away and it re-arms.

| Setting | What it does |
|---|---|
| `Dwell click` | On/off. |
| `Dwell hold time` | How long to hold still before it clicks. |
| `Dwell steadiness allowance` | How much drift is still "holding still". Raise it if it never fires. |
| `Dwell fires` | Which button it sends: left, right, or middle. |

Tap-to-click keeps working with dwell on.

### Cursor and gestures

| Setting | What it does |
|---|---|
| `Slow-move gain` / `Fast-flick gain` | Cursor speed floor and ceiling. |
| `Acceleration` | How quickly speed ramps between them. `0` = constant speed. |
| `Tap time limit` / `Tap wobble allowance` | How long and how loosely a touch can still count as a tap. Raise both if your taps are being read as drags. |
| `Press-and-hold to drag` | On/off. Turn it off if resting a finger keeps starting drags; use `Drag lock` instead. |
| `Hold time before drag` | How long to hold before the button goes down. Raise it if drags start unintentionally, lower it if holding feels slow. |
| `Hold wobble allowance` | How much the finger may drift during the hold. Raise it if the drag never starts; lower it if moving the cursor keeps turning into a drag. |
| `Scroll step` / `Zoom step` | Finger distance per scroll notch or zoom step. Lower = more sensitive. |
| `Scroll dead zone` / `Pinch dead zone` | How far two fingers travel before scrolling or pinching starts. |
| `Pinch decision delay` | Pause before deciding scroll-vs-pinch, so a two-finger start is not misread. |
| `Scroll-vs-pinch bias` | Which way ties break. Higher favours scrolling. |
| `Natural scroll — vertical` / `— horizontal` | Direction of each axis, set separately. |

### Where settings are stored

Settings are saved on the phone, per computer address, and survive reconnecting, restarting the
agent, and rebooting the PC. Two phones can hold different settings, which is the point.

They are keyed to the address in the URL, so if the computer's DHCP address changes, the phone
treats it as a new machine and the tuning appears to be gone. Reserve the address in your router
to avoid this. If it does happen, re-picking a preset is two taps.

## Troubleshooting

- **Phone cannot load the page** — confirm the server is running natively, both devices are on
  the same non-guest WiFi, and TCP port `8765` is allowed from the trusted LAN. Guest/AP isolation
  can block devices even when the WiFi name looks the same.
- **Installed phone icon stops connecting** — the computer's DHCP address probably changed.
  Reserve its address in the router, then scan and install the new URL once. Touch settings are
  stored per address, so they will look reset after such a change; re-pick a preset.
- **Phone seems to run an old version after updating the agent** — reload the page once with an
  extra parameter (`…&r=1`) to force a fresh copy. The page is served `no-store`, so this is only
  needed for a copy cached before that was added.
- **macOS moves/clicks do nothing** — grant Accessibility access to the exact Python interpreter
  printed by the installer, then restart the LaunchAgent or sign in again.
- **Linux reports no display** — launch from a graphical X11 session, not SSH or a TTY.
- **Linux Wayland controls only some apps** — those are Xwayland apps. Choose an Xorg session for
  complete control; `pynput`'s uinput backend is root-only and keyboard-only.
- **Startup logs** — Windows: `%LOCALAPPDATA%\remote-kbm\server.log`; macOS:
  `~/Library/Logs/remote-kbm/`; Linux: `${XDG_STATE_HOME:-~/.local/state}/remote-kbm/server.log`.

## Layout

- `server/main.py` — aiohttp: serves the page, handles the WebSocket, checks the token.
- `server/inject.py` — maps protocol messages to native mouse and keyboard calls.
- `server/runtime_check.py` — rejects WSL/Linux headless mistakes and warns about Wayland.
- `client/index.html` — the whole phone app (connection, trackpad, keyboard).
- `install.sh` / `uninstall.sh` — dispatch startup setup on macOS, Linux, and WSL.
- `windows/`, `macos/`, `linux/` — native per-user startup installers.
- `.github/workflows/ci.yml` — Windows/macOS/Linux checks on Python 3.10 and 3.14.

## License

[MIT](LICENSE)
