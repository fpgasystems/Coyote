#!/usr/bin/env python3
"""Verify files recorded in manifest.json.

By default this checks only VCS-trackable files. Use --include-non-vcs to also
verify heavy artifacts such as bitstreams, model weights, and prepared inputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("manifest.json"))
    parser.add_argument("--include-non-vcs", action="store_true")
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    root = manifest_path.parent
    manifest = json.loads(manifest_path.read_text())
    failures: list[str] = []
    checked = 0
    skipped = 0

    for entry in manifest["files"]:
        policy = entry.get("vcs_policy", "track")
        if policy != "track" and not args.include_non_vcs:
            skipped += 1
            continue
        rel = entry["path"]
        path = root / rel
        if not path.exists():
            failures.append(f"missing: {rel}")
            continue
        actual_size = path.stat().st_size
        if actual_size != entry["size_bytes"]:
            failures.append(f"size mismatch: {rel}: {actual_size} != {entry['size_bytes']}")
            continue
        actual_hash = sha256(path)
        if actual_hash != entry["sha256"]:
            failures.append(f"sha256 mismatch: {rel}: {actual_hash} != {entry['sha256']}")
            continue
        checked += 1

    print(f"checked={checked} skipped={skipped} failures={len(failures)}")
    for failure in failures:
        print(failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())

