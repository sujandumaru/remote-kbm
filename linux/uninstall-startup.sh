#!/bin/sh
set -eu

DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
RUNNER_PATH="$DATA_HOME/remote-kbm/run-at-login.sh"
DESKTOP_PATH="$CONFIG_HOME/autostart/remote-kbm.desktop"
PID_PATH="$STATE_HOME/remote-kbm/runner.pid"

rm -f -- "$DESKTOP_PATH"

if [ -s "$PID_PATH" ]; then
    PID=$(cat "$PID_PATH")
    case "$PID" in
        *[!0-9]*|'') ;;
        *)
            if [ -r "/proc/$PID/cmdline" ]; then
                CMDLINE=$(tr '\000' ' ' < "/proc/$PID/cmdline")
                case "$CMDLINE" in
                    *"$RUNNER_PATH"*) kill "$PID" 2>/dev/null || true ;;
                esac
            fi
            ;;
    esac
fi
rm -f -- "$PID_PATH" "$RUNNER_PATH"

echo "remote-kbm automatic startup was removed."
echo "Dependencies and logs were kept under:"
echo "  $DATA_HOME/remote-kbm"
echo "  $STATE_HOME/remote-kbm"
