#!/usr/bin/env python3
"""Verify generated hls4ml configs against manual per-layer tuning YAML."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))


def reexec_local_python_if_needed() -> None:
    if os.environ.get("HLS4ML_RUN_NO_VENV") == "1":
        return
    if os.environ.get("HLS4ML_VERIFY_LAYER_TUNING_REEXECED") == "1":
        return
    candidates = [
        EXAMPLE_ROOT.parent / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT.parent / ".venv" / "bin" / "python",
        EXAMPLE_ROOT / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT / ".venv" / "bin" / "python",
    ]
    current = Path(sys.executable)
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK) and candidate != current:
            os.environ["HLS4ML_VERIFY_LAYER_TUNING_REEXECED"] = "1"
            os.execv(str(candidate), [str(candidate), *sys.argv])


reexec_local_python_if_needed()

from pipeline.experiment_suite import metadata_for_config, write_csv
from pipeline.hls_layer_tuning import manual_layer_tuning
from pipeline.part1_common import build_context, load_config


def config_paths(inputs: list[Path]) -> list[Path]:
    paths: list[Path] = []
    for item in inputs:
        if item.is_dir():
            paths.extend(sorted(item.glob("*.yaml")))
            paths.extend(sorted(item.glob("*.yml")))
        else:
            paths.append(item)
    seen: set[Path] = set()
    out: list[Path] = []
    for path in paths:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            out.append(resolved)
    return out


def latest_matching_sweep(run_root: Path, sweep_name: str) -> Path | None:
    sweep_dir = run_root / "hls_sweeps"
    if not sweep_dir.exists():
        return None
    matches = [path for path in sweep_dir.glob(f"{sweep_name}_hls_*") if path.is_dir()]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def full_hls_config_path(config_path: Path, config: dict[str, Any]) -> Path:
    selected_run_root = config.get("experiment", {}).get("selected_run_root")
    ctx = build_context(
        config,
        config_path=config_path,
        run_root_arg=Path(selected_run_root) if selected_run_root else None,
    )
    direct = ctx.hls_sweep_root / f"fold_{int(config['candidate'].get('primary_fold', 0))}" / "project" / "full_hls_config.json"
    if direct.exists():
        return direct
    latest = latest_matching_sweep(ctx.run_root, str(config["hls"]["sweep_name"]))
    if latest is not None:
        return latest / f"fold_{int(config['candidate'].get('primary_fold', 0))}" / "project" / "full_hls_config.json"
    return direct


def verify_config(config_path: Path, require_synthesis: bool) -> tuple[list[dict[str, Any]], bool]:
    try:
        config = load_config(config_path)
        manual = manual_layer_tuning(config)
        meta = metadata_for_config(config, config_path)
    except Exception as exc:
        return (
            [
                {
                    "experiment_name": "",
                    "layer": "",
                    "expected_strategy": "",
                    "actual_strategy": "",
                    "expected_reuse_factor": "",
                    "actual_reuse_factor": "",
                    "status": "invalid_config",
                    "reason": str(exc),
                    "config_path": str(config_path),
                    "full_hls_config": "",
                }
            ],
            False,
        )

    experiment_name = str(meta["experiment_name"])
    if not manual:
        return (
            [
                {
                    "experiment_name": experiment_name,
                    "layer": "",
                    "expected_strategy": "",
                    "actual_strategy": "",
                    "expected_reuse_factor": "",
                    "actual_reuse_factor": "",
                    "status": "skipped_no_manual_tuning",
                    "reason": "",
                    "config_path": str(config_path),
                    "full_hls_config": "",
                }
            ],
            True,
        )

    full_config = full_hls_config_path(config_path, config)
    if not full_config.exists():
        return (
            [
                {
                    "experiment_name": experiment_name,
                    "layer": "",
                    "expected_strategy": "",
                    "actual_strategy": "",
                    "expected_reuse_factor": "",
                    "actual_reuse_factor": "",
                    "status": "missing_full_hls_config",
                    "reason": "run HLS first",
                    "config_path": str(config_path),
                    "full_hls_config": str(full_config),
                }
            ],
            False,
        )

    payload = json.loads(full_config.read_text())
    layer_configs = payload.get("LayerName", {})
    rows: list[dict[str, Any]] = []
    ok = True
    for layer, expected in manual.items():
        actual = layer_configs.get(layer, {})
        actual_strategy = actual.get("Strategy", "")
        actual_reuse = actual.get("ReuseFactor", "")
        status = "success"
        reason = ""
        try:
            actual_reuse_int = int(actual_reuse)
        except (TypeError, ValueError):
            actual_reuse_int = None
        if layer not in layer_configs:
            status = "missing_layer"
            reason = "layer not present in full_hls_config.json"
        elif actual_strategy != expected["Strategy"] or actual_reuse_int != int(expected["ReuseFactor"]):
            status = "mismatch"
            reason = "generated Strategy/ReuseFactor do not match YAML"
        if status != "success":
            ok = False
        rows.append(
            {
                "experiment_name": experiment_name,
                "layer": layer,
                "expected_strategy": expected["Strategy"],
                "actual_strategy": actual_strategy,
                "expected_reuse_factor": expected["ReuseFactor"],
                "actual_reuse_factor": actual_reuse,
                "status": status,
                "reason": reason,
                "config_path": str(config_path),
                "full_hls_config": str(full_config),
            }
        )

    if require_synthesis:
        synth_path = full_config.parents[2] / "synthesis_summary.csv"
        if not synth_path.exists():
            ok = False
            rows.append(
                {
                    "experiment_name": experiment_name,
                    "layer": "",
                    "expected_strategy": "",
                    "actual_strategy": "",
                    "expected_reuse_factor": "",
                    "actual_reuse_factor": "",
                    "status": "missing_synthesis",
                    "reason": "synthesis_summary.csv not found",
                    "config_path": str(config_path),
                    "full_hls_config": str(full_config),
                }
            )
    return rows, ok


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--configs",
        nargs="+",
        type=Path,
        required=True,
        help="YAML config files or directories containing YAML configs",
    )
    parser.add_argument("--results-dir", type=Path, default=Path("results/hand_tuning"))
    parser.add_argument("--require-synthesis", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    paths = config_paths(args.configs)
    if not paths:
        raise SystemExit("no config files found")

    all_rows: list[dict[str, Any]] = []
    ok = True
    for path in paths:
        rows, config_ok = verify_config(path, args.require_synthesis)
        all_rows.extend(rows)
        ok = ok and config_ok

    args.results_dir.mkdir(parents=True, exist_ok=True)
    out_csv = args.results_dir / "verification_outputs.csv"
    write_csv(out_csv, all_rows)
    failures = [row for row in all_rows if row.get("status") not in {"success", "skipped_no_manual_tuning"}]
    successes = [row for row in all_rows if row.get("status") == "success"]
    print(f"[verify-layer-tuning] configs={len(paths)} layers_ok={len(successes)} failures={len(failures)}")
    print(f"[verify-layer-tuning] wrote {out_csv}")
    if not ok:
        for row in failures[:20]:
            print(
                "[verify-layer-tuning] failure "
                f"experiment={row.get('experiment_name')} layer={row.get('layer')} "
                f"status={row.get('status')} reason={row.get('reason')}"
            )
        raise SystemExit(1)


if __name__ == "__main__":
    main()
