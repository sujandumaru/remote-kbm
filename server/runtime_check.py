"""Native-desktop runtime checks with actionable errors."""
import os
import platform
import sys


def is_wsl():
    """Return True only for a Linux Python process running inside WSL."""
    if not sys.platform.startswith("linux"):
        return False
    if os.environ.get("WSL_INTEROP") or os.environ.get("WSL_DISTRO_NAME"):
        return True
    try:
        release = platform.release().lower()
        return "microsoft" in release or "wsl" in release
    except OSError:
        return False


def check_runtime():
    """Return warnings, or raise RuntimeError when injection cannot target the desktop."""
    if is_wsl():
        raise RuntimeError(
            "WSL cannot control the Windows desktop. Run this project with Windows Python. "
            "From the repository, run ./install.sh to install the Windows startup task, "
            "or follow the WSL section in README.md."
        )

    warnings = []
    if sys.platform.startswith("linux"):
        session_type = os.environ.get("XDG_SESSION_TYPE", "").lower()
        if not os.environ.get("DISPLAY"):
            raise RuntimeError(
                "No graphical X display was found (DISPLAY is unset). Run remote-kbm "
                "from the signed-in desktop session, not SSH, a TTY, or a system service."
            )
        if session_type == "wayland" or os.environ.get("WAYLAND_DISPLAY"):
            warnings.append(
                "Wayland detected: pynput works only through Xwayland and cannot control "
                "native Wayland applications reliably. For full support, sign in using "
                "an Xorg/X11 session."
            )
    return warnings


def describe_runtime():
    if is_wsl():
        return "WSL (Windows target requires Windows Python)"
    return f"{platform.system()} {platform.release()} / Python {platform.python_version()}"
