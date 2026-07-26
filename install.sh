#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SYSTEM=$(uname -s)

case "$SYSTEM" in
    Darwin)
        exec "$SCRIPT_DIR/macos/install-startup.sh"
        ;;
    Linux)
        if [ -n "${WSL_INTEROP:-}" ] || [ -n "${WSL_DISTRO_NAME:-}" ] ||
            grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
            if ! command -v wslpath >/dev/null 2>&1 ||
                ! command -v powershell.exe >/dev/null 2>&1; then
                echo "ERROR: WSL-to-Windows interoperability is unavailable." >&2
                echo "Open Windows PowerShell and run windows\\install-startup.ps1 there." >&2
                exit 2
            fi
            WINDOWS_INSTALLER=$(wslpath -w "$SCRIPT_DIR/windows/install-startup.ps1")
            exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_INSTALLER"
        fi
        exec "$SCRIPT_DIR/linux/install-startup.sh"
        ;;
    *)
        echo "ERROR: Unsupported shell environment: $SYSTEM" >&2
        echo "On Windows, run .\\windows\\install-startup.ps1 in PowerShell." >&2
        exit 2
        ;;
esac
