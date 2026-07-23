import io
import sys
import types
import unittest
from pathlib import Path
from unittest import mock

SERVER_DIR = Path(__file__).resolve().parents[1] / "server"
sys.path.insert(0, str(SERVER_DIR))

import main  # noqa: E402


class MainHelpersTest(unittest.TestCase):
    def test_lan_ip_falls_back_when_socket_creation_fails(self):
        with mock.patch.object(main.socket, "socket", side_effect=PermissionError("blocked")):
            self.assertEqual(main.lan_ip(), "127.0.0.1")

    def test_qr_encoding_failure_still_prints_url(self):
        class BrokenQr:
            def __init__(self, **kwargs):
                self.options = kwargs

            def add_data(self, url):
                self.url = url

            def print_ascii(self, invert):
                raise UnicodeEncodeError("cp1252", "█", 0, 1, "unsupported")

        fake_qrcode = types.SimpleNamespace(QRCode=BrokenQr)
        output = io.StringIO()
        with (
            mock.patch.dict(sys.modules, {"qrcode": fake_qrcode}),
            mock.patch("sys.stdout", output),
        ):
            main.print_connection("http://192.168.1.2:8765/?k=test")

        self.assertIn("QR unavailable", output.getvalue())
        self.assertIn("http://192.168.1.2:8765/?k=test", output.getvalue())

    def test_show_connect_does_not_initialize_input_backend(self):
        with (
            mock.patch.object(main, "connect_url", return_value="http://example.test"),
            mock.patch.object(main, "print_connection") as print_connection,
            mock.patch.object(main, "check_runtime", side_effect=AssertionError("must not run")),
        ):
            main.main(["--show-connect"])

        print_connection.assert_called_once_with("http://example.test")


if __name__ == "__main__":
    unittest.main()
