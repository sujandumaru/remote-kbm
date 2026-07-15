"""Map wire-protocol messages (see plans/01-mvp.md) to OS input via pynput.

Nothing here executes strings from the wire; every message routes through an
explicit branch. `mouse` and `keyboard` are module globals so the self-check at
the bottom can swap in recording stubs and run headless.
"""
import contextlib
import logging

from pynput.mouse import Button, Controller as MouseController
from pynput.keyboard import Key, Controller as KeyboardController

log = logging.getLogger("inject")

mouse = MouseController()
keyboard = KeyboardController()

BUTTONS = {"left": Button.left, "right": Button.right, "middle": Button.middle}

MODS = {"ctrl": Key.ctrl, "alt": Key.alt, "shift": Key.shift, "cmd": Key.cmd}

SPECIAL = {
    "enter": Key.enter, "esc": Key.esc, "tab": Key.tab,
    "backspace": Key.backspace, "delete": Key.delete, "space": Key.space,
    "up": Key.up, "down": Key.down, "left": Key.left, "right": Key.right,
    "home": Key.home, "end": Key.end, "page_up": Key.page_up, "page_down": Key.page_down,
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
            mouse.move(int(msg["dx"]), int(msg["dy"]))
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
