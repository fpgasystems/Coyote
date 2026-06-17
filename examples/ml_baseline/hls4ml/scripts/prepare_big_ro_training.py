#!/usr/bin/env python3
"""Prepare isolated configs for unbalanced big-RO training."""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

SOURCE_VAULT = Path("/mnt/scratch/sdeheredia/coyote_vault_big_ro")
CONFIG_DIR = Path("configs/hls4ml_big_ro_training")
RESULTS_DIR = Path("results/big_ro_training")
OUTPUT_ROOT = "artifacts_big_ro"
MIN_RO = 8000

FLOAT_CONFIGS = {
    "res128_layers6_WfloatAfloat_P0_RFbase": Path(
        "configs/hls4ml_experiment_layer6_ext/res128_layers6_WfloatAfloat_P0_RFbase.yaml"
    ),
    "res256_layers7_WfloatAfloat_P0_RFbase": Path(
        "configs/hls4ml_experiment_layer7_ext/res256_layers7_WfloatAfloat_P0_RFbase.yaml"
    ),
    "res512_layers7_WfloatAfloat_P0_RFbase": Path(
        "configs/hls4ml_experiment_layer7_ext/res512_layers7_WfloatAfloat_P0_RFbase.yaml"
    ),
}

QAT_CONFIGS = {
    "res128_layers6_W8A8_P50_RFbase": Path(
        "configs/hls4ml_selected_feasible_candidates/res128_layers6_W8A8_P50_RFbase.yaml"
    ),
    "res256_layers7_W8A8_P50_RFbase": Path(
        "configs/hls4ml_selected_feasible_candidates/res256_layers7_W8A8_P50_RFbase.yaml"
    ),
    "res512_layers7_W8A8_P50_RFbase": Path(
        "configs/hls4ml_selected_feasible_candidates/res512_layers7_W8A8_P50_RFbase.yaml"
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-vault", type=Path, default=SOURCE_VAULT)
    parser.add_argument("--config-dir", type=Path, default=CONFIG_DIR)
    parser.add_argument("--results-dir", type=Path, default=RESULTS_DIR)
    parser.add_argument("--output-root", default=OUTPUT_ROOT)
    parser.add_argument("--min-ro", type=int, default=MIN_RO)
    parser.add_argument(
        "--reuse-existing-configs",
        action="store_true",
        help="Validate and reuse existing generated configs instead of failing.",
    )
    return parser.parse_args()


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def effective_counts(source_vault: Path, min_ro: int) -> tuple[Counter[str], list[str]]:
    counts: Counter[str] = Counter()
    missing: list[str] = []
    if not source_vault.is_dir():
        raise FileNotFoundError(f"missing source vault: {source_vault}")
    for dataset in sorted(path for path in source_vault.iterdir() if path.is_dir() and path.name.startswith("full_dataset_")):
        manifest = dataset / "manifest.csv"
        bitstreams = dataset / "bitstreams"
        if not manifest.exists():
            continue
        with manifest.open(newline="") as handle:
            for row in csv.DictReader(handle):
                class_label = str(row["class_label"])
                ro_count = int(float(row["ro_count"]))
                if class_label != "0" and ro_count < min_ro:
                    continue
                bitstream = bitstreams / row["bitstream_path"]
                if not bitstream.exists():
                    missing.append(f"{dataset.name}:{row['sample_id']}:{row['bitstream_path']}")
                    continue
                counts[class_label] += 1
    return counts, missing


def validate_existing_configs(config_dir: Path, source_vault_text: str, min_ro: int) -> list[dict[str, str]]:
    import yaml

    paths = sorted(config_dir.glob("*.yaml"))
    if len(paths) != 6:
        raise RuntimeError(f"expected 6 generated configs in {config_dir}, found {len(paths)}")
    rows = []
    for path in paths:
        cfg = yaml.safe_load(path.read_text()) or {}
        data = cfg.get("data", {}) or {}
        candidate = cfg.get("candidate", {}) or {}
        if str(data.get("train_vault_base")) != source_vault_text:
            raise RuntimeError(f"{path}: train_vault_base={data.get('train_vault_base')!r}, expected {source_vault_text}")
        if int(candidate.get("min_ro")) != min_ro:
            raise RuntimeError(f"{path}: min_ro={candidate.get('min_ro')!r}, expected {min_ro}")
        if bool(candidate.get("balance_classes", True)):
            raise RuntimeError(f"{path}: balance_classes must be false")
        rows.append(
            {
                "experiment_name": str(cfg.get("experiment", {}).get("name") or cfg.get("run", {}).get("iteration_name")),
                "phase": str(cfg.get("experiment", {}).get("phase", "")),
                "config_path": str(path),
                "source_config": str(cfg.get("experiment", {}).get("source_config", "")),
            }
        )
    return rows


def write_training_configs(
    config_dir: Path,
    results_dir: Path,
    source_vault_text: str,
    output_root: str,
    min_ro: int,
    *,
    reuse_existing_configs: bool,
) -> list[dict[str, str]]:
    import yaml

    if config_dir.exists() and any(config_dir.glob("*.yaml")):
        if reuse_existing_configs:
            rows = validate_existing_configs(config_dir, source_vault_text, min_ro)
            write_csv(
                results_dir / "big_ro_config_manifest.csv",
                rows,
                ["experiment_name", "phase", "config_path", "source_config"],
            )
            return rows
        raise FileExistsError(f"config dir already contains YAML files: {config_dir}")

    config_dir.mkdir(parents=True, exist_ok=True)
    results_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    for phase, sources in [("float", FLOAT_CONFIGS), ("qat_p50", QAT_CONFIGS)]:
        for name, source_rel in sources.items():
            source = EXAMPLE_ROOT / source_rel
            if not source.exists():
                raise FileNotFoundError(source)
            cfg = yaml.safe_load(source.read_text()) or {}
            cfg.setdefault("data", {})
            cfg["data"]["train_vault_base"] = source_vault_text
            cfg.setdefault("candidate", {})
            cfg["candidate"]["min_ro"] = int(min_ro)
            cfg["candidate"]["balance_classes"] = False
            cfg.setdefault("run", {})
            cfg["run"]["output_root"] = output_root
            cfg["run"]["timestamped_root"] = False
            cfg.setdefault("experiment", {})
            cfg["experiment"]["name"] = name
            cfg["experiment"]["phase"] = phase
            cfg["experiment"]["suite"] = "hls4ml_big_ro_training"
            cfg["experiment"]["tier"] = cfg["experiment"].get("tier") or "green"
            cfg["experiment"]["source_config"] = str(source)
            cfg["experiment"]["train_vault_base"] = source_vault_text
            cfg["experiment"]["class_balance"] = "disabled"
            cfg["experiment"]["qat_initialization"] = "scratch" if phase == "qat_p50" else ""
            out = config_dir / f"{name}.yaml"
            out.write_text(yaml.safe_dump(cfg, sort_keys=False))
            rows.append({"experiment_name": name, "phase": phase, "config_path": str(out), "source_config": str(source)})
    write_csv(
        results_dir / "big_ro_config_manifest.csv",
        rows,
        ["experiment_name", "phase", "config_path", "source_config"],
    )
    return rows


def main() -> None:
    args = parse_args()
    source_vault_text = str(args.source_vault)
    source_vault = args.source_vault.resolve()
    config_dir = (EXAMPLE_ROOT / args.config_dir).resolve() if not args.config_dir.is_absolute() else args.config_dir.resolve()
    results_dir = (EXAMPLE_ROOT / args.results_dir).resolve() if not args.results_dir.is_absolute() else args.results_dir.resolve()

    counts, missing = effective_counts(source_vault, args.min_ro)
    summary_rows = [
        {
            "source_vault": source_vault_text,
            "effective_min_ro": args.min_ro,
            "effective_benign_rows": counts.get("0", 0),
            "effective_standalone_rows": counts.get("1", 0),
            "skipped_missing_bitstreams": len(missing),
            "first_missing_bitstream": missing[0] if missing else "",
            "balance_classes": False,
        }
    ]
    write_csv(
        results_dir / "big_ro_dataset_summary.csv",
        summary_rows,
        [
            "source_vault",
            "effective_min_ro",
            "effective_benign_rows",
            "effective_standalone_rows",
            "skipped_missing_bitstreams",
            "first_missing_bitstream",
            "balance_classes",
        ],
    )
    config_rows = write_training_configs(
        config_dir,
        results_dir,
        source_vault_text,
        args.output_root,
        args.min_ro,
        reuse_existing_configs=args.reuse_existing_configs,
    )
    print(f"[big-ro] source_vault={source_vault_text}")
    print(
        f"[big-ro] effective_min_ro={args.min_ro} benign={counts.get('0', 0)} "
        f"standalone={counts.get('1', 0)} balance_classes=false missing_bitstreams={len(missing)}"
    )
    print(f"[big-ro] configs={len(config_rows)} dir={config_dir}")
    print(f"[big-ro] results={results_dir}")


if __name__ == "__main__":
    main()
