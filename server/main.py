"""remote-kbm desktop agent: serves the phone client and injects its input.

Run: python server/main.py    (see README.md)
"""
import argparse
import asyncio
import hmac
import json
import logging
import secrets
import socket
import sys
from pathlib import Path

from runtime_check import check_runtime, describe_runtime

LOG_FORMAT = "%(levelname)s %(name)s: %(message)s"
MAX_LOG_BYTES = 5 * 1024 * 1024

logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
log = logging.getLogger("main")

PORT = 8765
CLIENT_DIR = Path(__file__).resolve().parent.parent / "client"
TOKEN_FILE = Path.home() / ".remote-kbm-token"


def load_token():
    """Persist the token so the QR/bookmark/PWA survives restarts (delete the file to rotate)."""
    try:
        t = TOKEN_FILE.read_text().strip()
        if t:
            return t
    except OSError:
        pass
    t = secrets.token_urlsafe(8)
    try:
        TOKEN_FILE.write_text(t)
    except OSError as e:
        log.warning("could not persist token (%s); using a session-only one", e)
    return t


TOKEN = None
inject = None
aiohttp = None
web = None


def configure_file_output(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        if path.exists() and path.stat().st_size > MAX_LOG_BYTES:
            backup = path.with_name(path.name + ".1")
            backup.unlink(missing_ok=True)
            path.replace(backup)
    except OSError:
        pass

    stream = path.open("a", encoding="utf-8", errors="backslashreplace", buffering=1)
    sys.stdout = stream
    sys.stderr = stream
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=stream, force=True)
    return stream


def lan_ip():
    """Best-effort primary LAN IP (no packets sent)."""
    s = None
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        if s is not None:
            s.close()


def connect_url():
    return f"http://{lan_ip()}:{PORT}/?k={TOKEN}"


def print_connection(url):
    print("\n  Scan this on your phone (same WiFi), or open the URL:\n", flush=True)
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.print_ascii(invert=True)
    except (ImportError, OSError, UnicodeError) as e:
        # Some Windows consoles cannot encode qrcode's block characters.
        print(f"  (QR unavailable in this terminal: {e})", flush=True)
    print("\n    " + url + "\n", flush=True)


async def index(request):
    response = web.FileResponse(CLIENT_DIR / "index.html")
    response.headers["Cache-Control"] = "no-cache"
    return response


async def manifest(request):
    # Home-screen apps need the token in start_url because their storage is isolated.
    if not hmac.compare_digest(request.query.get("k", ""), TOKEN):
        return web.Response(status=403, text="bad token")
    data = json.loads((CLIENT_DIR / "manifest.json").read_text())
    data["start_url"] = f"/?k={TOKEN}"
    return web.json_response(data)


async def ping(request):
    """Lets the client tell 'PC unreachable' apart from 'wrong token'."""
    ok = hmac.compare_digest(request.query.get("k", ""), TOKEN)
    return web.Response(status=204 if ok else 403)


async def icon(request):
    return web.FileResponse(CLIENT_DIR / "icon.png")


async def ws_handler(request):
    if not hmac.compare_digest(request.query.get("k", ""), TOKEN):
        log.warning("rejected WS with bad token from %s", request.remote)
        return web.Response(status=403, text="bad token")

    ws = web.WebSocketResponse()
    await ws.prepare(request)
    log.info("client connected: %s", request.remote)
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            try:
                inject.handle(json.loads(msg.data))
            except json.JSONDecodeError:
                log.warning("non-JSON frame ignored")
        elif msg.type == aiohttp.WSMsgType.ERROR:
            log.warning("ws error: %s", ws.exception())
    log.info("client disconnected: %s", request.remote)
    return ws


async def quiet_disconnects(app):
    # Suppress harmless browser resets without hiding other event-loop errors.
    loop = asyncio.get_running_loop()

    def handler(lp, ctx):
        if isinstance(ctx.get("exception"), (ConnectionResetError, ConnectionAbortedError)):
            return
        lp.default_exception_handler(ctx)

    loop.set_exception_handler(handler)


def main(argv=None):
    parser = argparse.ArgumentParser(description="remote-kbm desktop agent")
    parser.add_argument(
        "--show-connect",
        action="store_true",
        help="print the saved QR/URL and exit without starting another server",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        help="write output to a file for windowless background startup",
    )
    args = parser.parse_args(argv)
    if args.log_file:
        configure_file_output(args.log_file)

    global TOKEN
    TOKEN = load_token()
    if args.show_connect:
        print_connection(connect_url())
        return

    global aiohttp, inject, web
    import aiohttp as aiohttp_module
    from aiohttp import web as web_module

    aiohttp = aiohttp_module
    web = web_module

    try:
        warnings = check_runtime()
    except RuntimeError as e:
        raise SystemExit(f"\nERROR: {e}\n") from None

    try:
        import inject as inject_module
    except ImportError as e:
        raise SystemExit(
            "\nERROR: Could not initialize desktop input control. "
            f"Check the OS setup notes in README.md.\n\n{e}\n"
        ) from None
    inject = inject_module

    log.info("runtime: %s", describe_runtime())
    for warning in warnings:
        log.warning(warning)

    app = web.Application()
    app.on_startup.append(quiet_disconnects)
    app.add_routes([web.get("/", index), web.get("/ws", ws_handler),
                    web.get("/manifest.json", manifest), web.get("/icon.png", icon),
                    web.get("/ping", ping)])
    url = connect_url()
    if args.log_file:
        log.info("connect URL: %s", url)
    else:
        print_connection(url)
    web.run_app(app, host="0.0.0.0", port=PORT, print=None)


if __name__ == "__main__":
    main()
