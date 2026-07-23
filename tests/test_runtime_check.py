import sys
import unittest
from pathlib import Path
from unittest import mock

SERVER_DIR = Path(__file__).resolve().parents[1] / "server"
sys.path.insert(0, str(SERVER_DIR))

import runtime_check  # noqa: E402


class RuntimeCheckTest(unittest.TestCase):
    def linux(self, environment):
        return (
            mock.patch.object(runtime_check.sys, "platform", "linux"),
            mock.patch.object(runtime_check.platform, "release", return_value="6.8.0-generic"),
            mock.patch.dict(runtime_check.os.environ, environment, clear=True),
        )

    def test_wsl_is_rejected(self):
        platform_patch, release_patch, environment_patch = self.linux(
            {"WSL_DISTRO_NAME": "Ubuntu", "DISPLAY": ":0"}
        )
        with platform_patch, release_patch, environment_patch:
            with self.assertRaisesRegex(RuntimeError, "Windows Python"):
                runtime_check.check_runtime()

    def test_headless_linux_is_rejected(self):
        platform_patch, release_patch, environment_patch = self.linux({})
        with platform_patch, release_patch, environment_patch:
            with self.assertRaisesRegex(RuntimeError, "DISPLAY is unset"):
                runtime_check.check_runtime()

    def test_wayland_gets_clear_warning(self):
        platform_patch, release_patch, environment_patch = self.linux(
            {"DISPLAY": ":0", "WAYLAND_DISPLAY": "wayland-0", "XDG_SESSION_TYPE": "wayland"}
        )
        with platform_patch, release_patch, environment_patch:
            warnings = runtime_check.check_runtime()
        self.assertEqual(len(warnings), 1)
        self.assertIn("Xorg/X11", warnings[0])

    def test_windows_has_no_linux_warnings(self):
        with (
            mock.patch.object(runtime_check.sys, "platform", "win32"),
            mock.patch.dict(runtime_check.os.environ, {}, clear=True),
        ):
            self.assertEqual(runtime_check.check_runtime(), [])


if __name__ == "__main__":
    unittest.main()
