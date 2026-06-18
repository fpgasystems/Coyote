#!/usr/bin/env python3
import hashlib, json
from pathlib import Path
root = Path(__file__).resolve().parent
manifest = json.loads((root / "manifest.json").read_text())
for item in manifest["files"]:
    path = root / item["path"]
    if not path.exists():
        raise SystemExit(f"missing {path}")
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    if path.stat().st_size != item["bytes"] or h.hexdigest() != item["sha256"]:
        raise SystemExit(f"mismatch {path}")
print("manifest OK")
