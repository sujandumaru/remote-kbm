import runpy
import site
import sys
from pathlib import Path


if len(sys.argv) < 4:
    raise SystemExit("usage: launch-background.pyw SITE_PACKAGES SERVER LOG [SERVER_ARGS...]")

site_packages = Path(sys.argv[1]).resolve()
server_path = Path(sys.argv[2]).resolve()
log_path = Path(sys.argv[3]).resolve()

site.addsitedir(str(site_packages))
sys.path.insert(0, str(server_path.parent))
sys.argv = [str(server_path), "--log-file", str(log_path), *sys.argv[4:]]
runpy.run_path(str(server_path), run_name="__main__")
