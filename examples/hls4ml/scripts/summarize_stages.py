#!/usr/bin/env python3
"""Collect stage metric summaries into one CSV for easier comparison."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-root", type=Path, default=Path("artifacts"))
    parser.add_argument("--output", type=Path, default=Path("artifacts/stage_summary.csv"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = []
    for summary_path in sorted(args.artifact_root.glob("**/metrics_summary.json")):
        payload = json.loads(summary_path.read_text())
        payload["summary_path"] = str(summary_path)
        rows.append(payload)

    if not rows:
        raise SystemExit(f"No metrics_summary.json files found under {args.artifact_root}")

    fieldnames = sorted({key for row in rows for key in row.keys()})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {args.output}")


if __name__ == "__main__":
    main()
