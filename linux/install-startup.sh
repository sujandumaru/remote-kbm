#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
PYTHON_BOOTSTRAP=${PYTHON_BOOTSTRAP:-python3}
DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
DATA_DIR="$DATA_HOME/remote-kbm"
STATE_DIR="$STATE_HOME/remote-kbm"
APP_DIR="$DATA_DIR/app"
VENV_DIR="$DATA_DIR/venv"
PYTHON_PATH="$VENV_DIR/bin/python"
RUNNER_PATH="$DATA_DIR/run-at-login.sh"
AUTOSTART_DIR="$CONFIG_HOME/autostart"
DESKTOP_PATH="$AUTOSTART_DIR/remote-kbm.desktop"
SERVER_PATH="$APP_DIR/server/main.py"
REQUIREMENTS_PATH="$PROJECT_ROOT/requirements.txt"
LOG_PATH="$STATE_DIR/server.log"
PID_PATH="$STATE_DIR/runner.pid"

if [ "$(uname -s)" != "Linux" ]; then
    echo "ERROR: This installer is for native Linux. Run ./install.sh instead." >&2
    exit 2
fi
if [ -n "${WSL_INTEROP:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ] ||
    grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
    echo "ERROR: Do not install the Linux agent inside WSL." >&2
    echo "Run ./install.sh from the repository root; it will install the Windows agent." >&2
    exit 2
fi
if ! command -v "$PYTHON_BOOTSTRAP" >/dev/null 2>&1; then
    echo "ERROR: python3 was not found. Install Python 3.10+ and its venv module." >&2
    exit 2
fi
if ! "$PYTHON_BOOTSTRAP" -c 'import sys; assert sys.version_info >= (3, 10)' 2>/dev/null; then
    echo "ERROR: Python 3.10 or newer is required." >&2
    exit 2
fi

mkdir -p "$DATA_DIR" "$STATE_DIR" "$AUTOSTART_DIR"
if [ ! -x "$PYTHON_PATH" ]; then
    echo "Creating isolated environment at $VENV_DIR"
    if ! "$PYTHON_BOOTSTRAP" -m venv "$VENV_DIR"; then
        echo "ERROR: Python's venv module is unavailable." >&2
        echo "On Debian/Ubuntu, install the python3-venv package and retry." >&2
        exit 2
    fi
fi

echo "Installing remote-kbm dependencies..."
"$PYTHON_PATH" -m pip install --disable-pip-version-check -r "$REQUIREMENTS_PATH"

# Import using a dummy backend so installation can also be performed from a TTY.
PYNPUT_BACKEND=dummy "$PYTHON_PATH" -c 'import aiohttp, pynput, qrcode'

mkdir -p "$APP_DIR/server" "$APP_DIR/client"
cp "$PROJECT_ROOT"/server/*.py "$APP_DIR/server/"
cp -R "$PROJECT_ROOT/client/." "$APP_DIR/client/"

"$PYTHON_PATH" - "$RUNNER_PATH" "$DESKTOP_PATH" "$PYTHON_PATH" "$SERVER_PATH" \
    "$APP_DIR/client/icon.png" "$LOG_PATH" "$PID_PATH" <<'PY'
import os
import shlex
import stat
import sys

runner, desktop, python_path, server, icon, log, pid = sys.argv[1:]

runner_text = f"""#!/bin/sh
set -u
LOG={shlex.quote(log)}
PID={shlex.quote(pid)}
PYTHON={shlex.quote(python_path)}
SERVER={shlex.quote(server)}
mkdir -p -- "$(dirname -- "$LOG")"
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 5242880 ]; then
    mv -f -- "$LOG" "$LOG.1"
fi
echo $$ > "$PID"
trap 'rm -f -- "$PID"' EXIT
child_pid=
stop_runner() {{
    trap - HUP INT TERM
    if [ -n "$child_pid" ]; then
        kill "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
    fi
    exit 0
}}
trap stop_runner HUP INT TERM
attempt=1
while [ "$attempt" -le 3 ]; do
    "$PYTHON" "$SERVER" >> "$LOG" 2>&1 &
    child_pid=$!
    wait "$child_pid"
    code=$?
    child_pid=
    [ "$code" -eq 0 ] && exit 0
    printf '[%s] remote-kbm exited with code %s (attempt %s/3)\\n' \\
        "$(date '+%Y-%m-%d %H:%M:%S')" "$code" "$attempt" >> "$LOG"
    attempt=$((attempt + 1))
    sleep 10
done
exit "$code"
"""
with open(runner, "w", encoding="utf-8", newline="\n") as stream:
    stream.write(runner_text)
os.chmod(runner, os.stat(runner).st_mode | stat.S_IXUSR)


def desktop_quote(value):
    escaped = ""
    for char in value:
        if char == "\\":
            escaped += "\\\\\\\\"
        elif char in {'"', '`', '$'}:
            escaped += "\\\\" + char
        else:
            escaped += char
    return f'"{escaped}"'


desktop_text = f"""[Desktop Entry]
Type=Application
Version=1.5
Name=remote-kbm
Comment=Phone trackpad and keyboard server
Exec={desktop_quote(runner)}
Icon={icon}
Terminal=false
StartupNotify=false
NoDisplay=true
"""
with open(desktop, "w", encoding="utf-8", newline="\n") as stream:
    stream.write(desktop_text)
PY

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$DESKTOP_PATH"
fi

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo
    echo "WARNING: Wayland was detected."
    echo "pynput can control only Xwayland applications, not the full native Wayland desktop."
    echo "For full remote mouse and keyboard support, sign in using an Xorg/X11 session."
fi

if [ -s "$PID_PATH" ] && kill -0 "$(cat "$PID_PATH")" 2>/dev/null; then
    echo "remote-kbm is already running through the startup runner."
elif command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -qE '[:.]8765[[:space:]]'; then
    echo "A server is already using port 8765; automatic startup begins next login."
elif [ -n "${DISPLAY:-}" ]; then
    nohup "$RUNNER_PATH" >/dev/null 2>&1 &
    echo "Startup installed and launch requested."
else
    echo "Startup installed. It will launch after the next graphical sign-in."
fi

echo "Autostart entry: $DESKTOP_PATH"
echo "Log: $LOG_PATH"
echo "After an update, fully close and reopen the phone app."
echo "Allow inbound TCP port 8765 from your trusted LAN in the Linux firewall."
"$PYTHON_PATH" "$SERVER_PATH" --show-connect
