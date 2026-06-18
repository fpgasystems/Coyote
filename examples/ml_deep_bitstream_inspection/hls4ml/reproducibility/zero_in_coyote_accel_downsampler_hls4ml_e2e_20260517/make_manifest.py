#!/usr/bin/env python3
"""Create manifest.json for the raw downsampler zero-in package."""

from __future__ import annotations

import hashlib
import json
import socket
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
NON_VCS_PREFIXES = ("non_vcs_artifacts/", "replay/")
SKIP_PREFIXES = ("non_vcs_artifacts/raw_bitstreams/",)
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
        if rel in SKIP or rel.startswith(SKIP_PREFIXES):
            continue
        if rel.startswith("replay/"):
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
    performance = maybe_json("results/performance_summary.json")
    compile_smoke = maybe_json("results/compile_smoke/compile_smoke_summary.json")
    raw_manifest = maybe_json("non_vcs_artifacts/raw_bitstreams_by_vault/raw_manifest.json")
    manifest = {
        "name": "zero_in_coyote_accel_downsampler_hls4ml_e2e_20260517",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "created_on_host": socket.gethostname(),
        "root": str(ROOT),
        "source_revisions": {
            "coyote_repo": {
                "path": "/pub/scratch/sdeheredia/Coyote",
                "branch": "full-dataset-ml-baseline-1d",
                "commit": "214fc33ed2903c952ee22ab65efd20df13ccdd39",
            },
            "hls4ml_pr_checkout": {
                "path": "/pub/scratch/sdeheredia/hls4ml",
                "branch": "coyote-accelerator",
                "commit": "d4a6a2f5bee752e5d3738f136726fea722cc65e4",
            },
            "hls4ml_submodules": {
                "example-models": "e7a9dee394b6c1f6e0eb23178d34e55f077297fe",
                "hls4ml/contrib/Coyote": "292ec1521c4a9a1cc9b1335dee6b99deabb38542",
                "hls4ml/templates/catapult/ac_math": "3696be957d0b0fa0a285f90382d75c8a521d77ee",
                "hls4ml/templates/catapult/ac_simutils": "9dfe23415cf670ed7c990d9a6a237d06a5a62e57",
            },
        },
        "tool_versions": {
            "vitis_hls": "2024.2",
            "vivado": "2024.2",
            "python": "3.10",
            "hls4ml_checkout": "d4a6a2f5bee752e5d3738f136726fea722cc65e4",
        },
        "milestone_run": {
            "run_root": "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/20260516_183649",
            "zero_in_source_run": "/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/cnn_small_hls_opt_img256/notebook_pruned_qat/ZERO_IN_res256_layers5_W8A8_P50_RFbase_07faeca37cb7",
            "device": "Alveo U55C on alveo-u55c-09.inf.ethz.ch",
            "project_name": "zero_in_coyote_accel",
            "backend": "CoyoteAccelerator",
            "io_type": "io_stream",
            "input_mode": "raw bitstream bytes with FPGA-side downsampling",
        },
        "validation": validation,
        "performance": performance,
        "compile_smoke": compile_smoke,
        "raw_bitstreams": {
            "packaged_root": "non_vcs_artifacts/raw_bitstreams_by_vault",
            "count": len(raw_manifest or []),
            "manifest": "non_vcs_artifacts/raw_bitstreams_by_vault/raw_manifest.json",
            "split_csv": "non_vcs_artifacts/raw_bitstreams_by_vault/fold_0_val.csv",
        },
        "files": file_entries(),
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(ROOT / "manifest.json")


if __name__ == "__main__":
    main()
