"""remote-kbm desktop agent: serves the phone client and injects its input.

Run: python server/main.py    (see plans/01-mvp.md / README.md)
"""
import hmac
import json
import logging
import secrets
import socket
from pathlib import Path

import aiohttp
from aiohttp import web

import inject

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
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


TOKEN = load_token()


def lan_ip():
    """Best-effort primary LAN IP (no packets sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


async def index(request):
    return web.FileResponse(CLIENT_DIR / "index.html")


async def manifest(request):
    return web.FileResponse(CLIENT_DIR / "manifest.json")


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


def main():
    app = web.Application()
    app.add_routes([web.get("/", index), web.get("/ws", ws_handler),
                    web.get("/manifest.json", manifest), web.get("/icon.png", icon)])
    url = f"http://{lan_ip()}:{PORT}/?k={TOKEN}"
    print("\n  Scan this on your phone (same WiFi), or open the URL:\n", flush=True)
    try:
        import qrcode
        qr = qrcode.QRCode(border=1)
        qr.add_data(url)
        qr.print_ascii(invert=True)   # invert suits dark terminals; drop it on a light one
    except ImportError:
        pass                          # QR is optional; the URL below is enough
    print("\n    " + url + "\n", flush=True)
    web.run_app(app, port=PORT, print=None)


if __name__ == "__main__":
    main()
