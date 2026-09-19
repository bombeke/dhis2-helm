"""Fill EXTENSIONS_PATH with .supx bundles. Managed by the dashboard Helm chart.

usage: fetch_extensions.py DEST [SRC]

Copies every *.supx from SRC (the extensions.volume mount, if any), then
downloads each entry of extensions.bundles and verifies it against its
sha256. A mismatch is fatal: an extension runs code in every Superset
process, so a bundle that is not exactly the one pinned must not load.
"""

import hashlib
import hmac
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

MAX_BYTES = 256 * 1024 * 1024


def main() -> int:
    dest = Path(sys.argv[1])
    src = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    conf_dir = Path(os.environ.get("SUPERSET_CHART_CONF_DIR", "/etc/superset/conf"))
    settings = json.loads((conf_dir / "settings.json").read_text())
    bundles = settings["extensions"]["bundles"]

    if src and src.is_dir():
        for bundle in sorted(src.glob("*.supx")):
            shutil.copyfile(bundle, dest / bundle.name)
            print(f"copied {bundle.name} from the extensions volume")

    for bundle in bundles:
        name, url, expected = bundle["name"], bundle["url"], bundle["sha256"].lower()
        if not url.startswith("https://"):
            print(f"{name}: refusing non-HTTPS url", file=sys.stderr)
            return 1
        digest = hashlib.sha256()
        size = 0
        with tempfile.NamedTemporaryFile(dir=dest, delete=False) as tmp:
            try:
                with urllib.request.urlopen(url, timeout=60) as resp:  # noqa: S310
                    while chunk := resp.read(1 << 20):
                        size += len(chunk)
                        if size > MAX_BYTES:
                            raise ValueError(f"larger than {MAX_BYTES} bytes")
                        digest.update(chunk)
                        tmp.write(chunk)
            except Exception as exc:  # pylint: disable=broad-except
                os.unlink(tmp.name)
                print(f"{name}: download failed: {exc}", file=sys.stderr)
                return 1
        actual = digest.hexdigest()
        if not hmac.compare_digest(actual, expected):
            os.unlink(tmp.name)
            print(f"{name}: sha256 mismatch: expected {expected}, got {actual}", file=sys.stderr)
            return 1
        if not zipfile.is_zipfile(tmp.name):
            os.unlink(tmp.name)
            print(f"{name}: not a .supx (zip) bundle", file=sys.stderr)
            return 1
        os.replace(tmp.name, dest / f"{name}.supx")
        print(f"{name}: verified ({size} bytes)")

    for bundle in dest.glob("*.supx"):
        bundle.chmod(0o444)
    return 0


if __name__ == "__main__":
    sys.exit(main())
