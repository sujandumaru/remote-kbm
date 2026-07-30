import io
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

SERVER_DIR = Path(__file__).resolve().parents[1] / "server"
sys.path.insert(0, str(SERVER_DIR))

import main  # noqa: E402


class MainHelpersTest(unittest.TestCase):
    def test_client_version_tracks_client_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            client_dir = Path(directory)
            index = client_dir / "index.html"
            index.write_text("first")
            with mock.patch.object(main, "CLIENT_DIR", client_dir):
                first = main.client_version()
                index.write_text("second")
                second = main.client_version()

        self.assertEqual(len(first), 12)
        self.assertNotEqual(first, second)

    def test_connect_url_is_versioned(self):
        with (
            mock.patch.object(main, "lan_ip", return_value="192.168.1.2"),
            mock.patch.object(main, "client_version", return_value="abc123"),
            mock.patch.object(main, "TOKEN", "test-token"),
        ):
            self.assertEqual(
                main.connect_url(),
                "http://192.168.1.2:8765/?k=test-token&v=abc123",
            )

    def test_versioned_path_replaces_old_version(self):
        with mock.patch.object(main, "client_version", return_value="new"):
            self.assertEqual(
                main.versioned_path({"k": "test-token", "v": "old"}),
                "/?k=test-token&v=new",
            )

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


class WebSocketHandlerTest(unittest.IsolatedAsyncioTestCase):
    async def test_ready_ping_and_input_dispatch(self):
        messages = iter([
            types.SimpleNamespace(type="text", data='{"t":"ping"}'),
            types.SimpleNamespace(type="text", data='{"t":"move","dx":1,"dy":2}'),
        ])

        class FakeSocket:
            def __init__(self):
                self.sent = []

            async def prepare(self, request):
                self.request = request

            async def send_json(self, data):
                self.sent.append(data)

            def __aiter__(self):
                return self

            async def __anext__(self):
                try:
                    return next(messages)
                except StopIteration:
                    raise StopAsyncIteration

        socket = FakeSocket()
        heartbeat = []
        fake_web = types.SimpleNamespace(
            WebSocketResponse=lambda **kwargs: heartbeat.append(kwargs["heartbeat"]) or socket,
        )
        fake_aiohttp = types.SimpleNamespace(
            WSMsgType=types.SimpleNamespace(TEXT="text", ERROR="error"),
        )
        fake_inject = types.SimpleNamespace(handle=mock.Mock())
        request = types.SimpleNamespace(query={"k": "test"}, remote="phone")

        with (
            mock.patch.object(main, "TOKEN", "test"),
            mock.patch.object(main, "web", fake_web),
            mock.patch.object(main, "aiohttp", fake_aiohttp),
            mock.patch.object(main, "inject", fake_inject),
        ):
            response = await main.ws_handler(request)

        self.assertIs(response, socket)
        self.assertEqual(heartbeat, [10])
        self.assertEqual(socket.sent, [{"t": "ready"}, {"t": "pong"}])
        fake_inject.handle.assert_called_once_with({"t": "move", "dx": 1, "dy": 2})


if __name__ == "__main__":
    unittest.main()
