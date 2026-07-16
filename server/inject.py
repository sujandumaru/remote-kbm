"""Map wire-protocol messages (see plans/01-mvp.md) to OS input via pynput.

Nothing here executes strings from the wire; every message routes through an
explicit branch. `mouse` and `keyboard` are module globals so the self-check at
the bottom can swap in recording stubs and run headless.
"""
import contextlib
import logging
import sys

from pynput.mouse import Button, Controller as MouseController
from pynput.keyboard import Key, Controller as KeyboardController

log = logging.getLogger("inject")

mouse = MouseController()
keyboard = KeyboardController()


def _abs_coords(x, y, dx, dy, vx, vy, vw, vh):
    """Map a target pixel (current + delta) into SendInput's 0..65535 virtual-desktop space."""
    ax = round((x + dx - vx) * 65535 / max(vw - 1, 1))
    ay = round((y + dy - vy) * 65535 / max(vh - 1, 1))
    return ax, ay


# On Windows, pynput moves the cursor with SetCursorPos, which Windows does NOT treat
# as mouse-device activity — so the pointer stays HIDDEN until a real mouse moves
# (the "invisible cursor" report). An ABSOLUTE SendInput move counts as real mouse
# input, revealing the pointer, and absolute coords bypass pointer-accel so our own
# client-side acceleration is the only one in play.
if sys.platform == "win32":
    import ctypes
    from ctypes import wintypes

    class _MOUSEINPUT(ctypes.Structure):
        _fields_ = (("dx", wintypes.LONG), ("dy", wintypes.LONG),
                    ("mouseData", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t))

    class _INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = (("mi", _MOUSEINPUT),)
        _anonymous_ = ("u",)
        _fields_ = (("type", wintypes.DWORD), ("u", _U))

    _u32 = ctypes.windll.user32
    _u32.SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(_INPUT), ctypes.c_int)
    _MOVE_ABS = 0x0001 | 0x8000 | 0x4000        # MOVE | ABSOLUTE | VIRTUALDESK
    _SM = (76, 77, 78, 79)                       # virtual screen X, Y, CX, CY

    def move_rel(dx, dy):
        pt = wintypes.POINT()
        _u32.GetCursorPos(ctypes.byref(pt))
        vx, vy, vw, vh = (_u32.GetSystemMetrics(m) for m in _SM)
        ax, ay = _abs_coords(pt.x, pt.y, dx, dy, vx, vy, vw, vh)
        inp = _INPUT()
        inp.type = 0                             # INPUT_MOUSE
        inp.mi = _MOUSEINPUT(ax, ay, 0, _MOVE_ABS, 0, 0)
        _u32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(inp))
else:
    def move_rel(dx, dy):
        mouse.move(dx, dy)

BUTTONS = {"left": Button.left, "right": Button.right, "middle": Button.middle}

MODS = {"ctrl": Key.ctrl, "alt": Key.alt, "shift": Key.shift, "cmd": Key.cmd}

SPECIAL = {
    "enter": Key.enter, "esc": Key.esc, "tab": Key.tab,
    "backspace": Key.backspace, "delete": Key.delete, "space": Key.space,
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
    "home": Key.home, "end": Key.end, "page_up": Key.page_up, "page_down": Key.page_down,
    "media_play_pause": Key.media_play_pause, "media_previous": Key.media_previous,
    "media_next": Key.media_next, "media_volume_mute": Key.media_volume_mute,
    "media_volume_down": Key.media_volume_down, "media_volume_up": Key.media_volume_up,
    **MODS,
    **{f"f{i}": getattr(Key, f"f{i}") for i in range(1, 13)},
}

_warned = set()


def _tap(name, mods):
    key = SPECIAL.get(name, name)  # single char passes straight through
    with contextlib.ExitStack() as stack:
        for m in mods:
            if m in MODS:
                stack.enter_context(keyboard.pressed(MODS[m]))
        keyboard.press(key)
        keyboard.release(key)


def handle(msg):
    """Dispatch one decoded JSON frame. Unknown/invalid frames are ignored."""
    t = msg.get("t")
    try:
        if t == "move":
            move_rel(int(msg["dx"]), int(msg["dy"]))
        elif t == "click":
            mouse.click(BUTTONS[msg["b"]], int(msg.get("n", 1)))
        elif t == "press":
            mouse.press(BUTTONS[msg["b"]])
        elif t == "release":
            mouse.release(BUTTONS[msg["b"]])
        elif t == "scroll":
            mouse.scroll(int(msg["dx"]), int(msg["dy"]))
        elif t == "zoom":
            with keyboard.pressed(Key.ctrl):
                mouse.scroll(0, int(msg["d"]))
        elif t == "key":
            _tap(msg["k"], msg.get("mods", []))
        elif t == "text":
            keyboard.type(str(msg["s"]))
        elif t not in _warned:
            _warned.add(t)
            log.warning("ignoring unknown message type: %r", t)
    except (KeyError, ValueError, TypeError) as e:
        log.warning("bad message %r: %s", msg, e)


def _selfcheck():
    global mouse, keyboard

    class RecMouse:
        def __init__(self): self.calls = []
        def move(self, dx, dy): self.calls.append(("move", dx, dy))
        def click(self, b, n): self.calls.append(("click", b, n))
        def press(self, b): self.calls.append(("press", b))
        def release(self, b): self.calls.append(("release", b))
        def scroll(self, dx, dy): self.calls.append(("scroll", dx, dy))

    class RecKb:
        def __init__(self): self.calls = []
        def type(self, s): self.calls.append(("type", s))
        def press(self, k): self.calls.append(("press", k))
        def release(self, k): self.calls.append(("release", k))
        @contextlib.contextmanager
        def pressed(self, *keys):
            self.calls.append(("hold", keys)); yield; self.calls.append(("drop", keys))

    mouse, keyboard = RecMouse(), RecKb()

    handle({"t": "move", "dx": 100, "dy": -5})
    assert mouse.calls[-1] == ("move", 100, -5)

    # abs-coord normalization. The screen sizes below are ARBITRARY EXAMPLE INPUTS for the
    # math only — at runtime move_rel() reads the real geometry from GetSystemMetrics, so any
    # resolution/monitor works. Case 1: corners & centre of an example 1920x1080 display.
    assert _abs_coords(0, 0, 0, 0, 0, 0, 1920, 1080) == (0, 0)
    assert _abs_coords(1919, 1079, 0, 0, 0, 0, 1920, 1080) == (65535, 65535)
    assert _abs_coords(900, 500, 60, 40, 0, 0, 1920, 1080) == (32785, 32798)
    # Case 2: a second monitor left of primary (negative virtual origin) still maps into range.
    assert _abs_coords(-1920, 0, 0, 0, -1920, 0, 3840, 1080) == (0, 0)

    handle({"t": "click", "b": "left", "n": 2})
    assert mouse.calls[-1] == ("click", Button.left, 2)

    handle({"t": "click", "b": "right"})
    assert mouse.calls[-1] == ("click", Button.right, 1)

    handle({"t": "press", "b": "left"}); assert mouse.calls[-1] == ("press", Button.left)
    handle({"t": "release", "b": "left"}); assert mouse.calls[-1] == ("release", Button.left)

    handle({"t": "scroll", "dx": 0, "dy": 2})
    assert mouse.calls[-1] == ("scroll", 0, 2)

    handle({"t": "zoom", "d": 1})
    assert keyboard.calls[-2:] == [("hold", (Key.ctrl,)), ("drop", (Key.ctrl,))]
    assert mouse.calls[-1] == ("scroll", 0, 1)

    handle({"t": "text", "s": "hello"})
    assert keyboard.calls[-1] == ("type", "hello")

    handle({"t": "key", "k": "enter"})
    assert keyboard.calls[-2:] == [("press", Key.enter), ("release", Key.enter)]

    handle({"t": "key", "k": "a"})  # plain char passes through
    assert keyboard.calls[-2:] == [("press", "a"), ("release", "a")]

    handle({"t": "key", "k": "media_volume_up"})
    assert keyboard.calls[-2:] == [
        ("press", Key.media_volume_up), ("release", Key.media_volume_up)]

    handle({"t": "key", "k": "c", "mods": ["ctrl"]})
    assert keyboard.calls[-4:] == [
        ("hold", (Key.ctrl,)), ("press", "c"), ("release", "c"), ("drop", (Key.ctrl,))]

    n = len(mouse.calls) + len(keyboard.calls)
    handle({"t": "nope"})                 # unknown -> ignored
    handle({"t": "move", "dx": "x"})      # bad payload -> ignored
    assert len(mouse.calls) + len(keyboard.calls) == n

    print("inject self-check OK")


if __name__ == "__main__":
    _selfcheck()
