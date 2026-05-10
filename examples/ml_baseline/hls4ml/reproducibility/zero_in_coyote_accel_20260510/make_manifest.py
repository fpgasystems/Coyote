#!/usr/bin/env python3
"""Create manifest.json for this reproducibility package."""

from __future__ import annotations

import hashlib
import json
import os
import socket
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
NON_VCS_PREFIXES = ("non_vcs_artifacts/", "replay/")
SKIP = {"manifest.json"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_entries() -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for path in sorted(p for p in ROOT.rglob("*") if p.is_file()):
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("replay/"):
            continue
        if rel in SKIP:
            continue
        policy = "ignore" if rel.startswith(NON_VCS_PREFIXES) else "track"
        entries.append(
            {
                "path": rel,
                "size_bytes": path.stat().st_size,
                "sha256": sha256(path),
                "vcs_policy": policy,
            }
        )
    return entries


def maybe_json(rel: str) -> dict[str, object] | None:
    path = ROOT / rel
    if not path.exists():
        return None
    return json.loads(path.read_text())


def main() -> None:
    validation = maybe_json("results/fpga_validation/validation_summary.json")
    compile_smoke = maybe_json("results/compile_smoke/compile_smoke_summary.json")
    manifest = {
        "name": "zero_in_coyote_accel_20260510",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "created_on_host": socket.gethostname(),
        "root": str(ROOT),
        "source_revisions": {
            "coyote_repo": {
                "path": "/pub/scratch/sdeheredia/Coyote",
                "branch": "full-dataset-ml-baseline-1d",
                "commit": "d3b507d29c33136294878ab67ab77763b17962c0",
            },
            "hls4ml_pr_checkout": {
                "path": "/pub/scratch/sdeheredia/hls4ml",
                "branch": "coyote-accelerator",
                "commit": "d4a6a2f5bee752e5d3738f136726fea722cc65e4",
            },
            "hls4ml_submodules": {
                "example-models": "e7a9dee394b6c1f6e0eb23178d34e55f077297fe",
                "hls4ml/contrib/Coyote": "292ec1521c4a9a1cc9b1335dee6b99deabb38542",
                "hls4ml/contrib/Coyote/hw/services/network": "9eda6ce9a55c0761ee9e66d1eba38ad5c9474aa9",
            },
        },
        "tool_versions": {
            "vitis_hls": "2024.2",
            "vivado": "2024.2",
            "python": "3.10.12",
            "tensorflow": "2.21.0",
            "keras": "3.12.1",
            "tf_keras": "2.21.0",
            "qkeras": "0.9.0",
            "numpy": "1.26.4",
            "hls4ml": "0.6.0.dev516+gd4a6a2f5",
        },
        "milestone_run": {
            "run_root": "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/20260509_173826",
            "zero_in_source_run": "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/cnn_small_hls_opt_img256/notebook_pruned_qat/ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7",
            "device": "Alveo U55C on alveo-u55c-07.inf.ethz.ch",
            "project_name": "zero_in_coyote_accel",
            "backend": "CoyoteAccelerator",
            "io_type": "io_stream",
        },
        "validation": validation,
        "compile_smoke": compile_smoke,
        "files": file_entries(),
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(ROOT / "manifest.json")


if __name__ == "__main__":
    main()
