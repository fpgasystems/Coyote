#!/usr/bin/env python3
"""Prepare a balanced big-RO vault and isolated training configs."""

from __future__ import annotations

import argparse
import csv
import os
import shutil
import sys
from collections import Counter
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

SOURCE_VAULT = Path("/mnt/scratch/sdeheredia/coyote_vault_big_ro")
DEST_VAULT = Path("/mnt/scratch/sdeheredia/coyote_vault_big_ro_balanced")
CONFIG_DIR = Path("configs/hls4ml_big_ro_balanced_training")
RESULTS_DIR = Path("results/big_ro_balanced_training")
OUTPUT_ROOT = "artifacts_big_ro_balanced"
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
    parser.add_argument("--dest-vault", type=Path, default=DEST_VAULT)
    parser.add_argument("--config-dir", type=Path, default=CONFIG_DIR)
    parser.add_argument("--results-dir", type=Path, default=RESULTS_DIR)
    parser.add_argument("--output-root", default=OUTPUT_ROOT)
    parser.add_argument("--min-ro", type=int, default=MIN_RO)
    parser.add_argument(
        "--reuse-existing-vault",
        action="store_true",
        help="Validate and reuse an existing destination vault instead of creating it.",
    )
    parser.add_argument(
        "--reuse-existing-configs",
        action="store_true",
        help="Validate and reuse existing generated configs instead of failing.",
    )
    return parser.parse_args()


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def should_keep_manifest_row(dataset_name: str, row: dict[str, str]) -> bool:
    if dataset_name == "full_dataset_it2_2026-04-08" and str(row.get("class_label")) == "1":
        return False
    return True


def should_keep_report_row(dataset_name: str, row: dict[str, str]) -> bool:
    if dataset_name == "full_dataset_it2_2026-04-08" and str(row.get("batch_id", "")).startswith("STAND"):
        return False
    return True


def link_or_copy(src: Path, dst: Path) -> str:
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)
        return "hardlink"
    except OSError:
        shutil.copy2(src, dst)
        return "copy"


def create_balanced_vault(source_vault: Path, dest_vault: Path, min_ro: int) -> list[dict[str, Any]]:
    if not source_vault.is_dir():
        raise FileNotFoundError(f"missing source vault: {source_vault}")
    if dest_vault.exists():
        raise FileExistsError(f"destination vault already exists: {dest_vault}")

    summaries: list[dict[str, Any]] = []
    dest_vault.mkdir(parents=True)
    for src_dataset in sorted(path for path in source_vault.iterdir() if path.is_dir() and path.name.startswith("full_dataset_")):
        dst_dataset = dest_vault / src_dataset.name
        dst_dataset.mkdir()

        manifest_path = src_dataset / "manifest.csv"
        if not manifest_path.exists():
            continue
        manifest_fields, manifest_rows = read_csv(manifest_path)
        kept_manifest_rows = [row for row in manifest_rows if should_keep_manifest_row(src_dataset.name, row)]
        write_csv(dst_dataset / "manifest.csv", manifest_fields, kept_manifest_rows)

        available_path = src_dataset / "manifest_available.csv"
        if available_path.exists():
            available_fields, available_rows = read_csv(available_path)
            kept_available_rows = [row for row in available_rows if should_keep_manifest_row(src_dataset.name, row)]
            write_csv(dst_dataset / "manifest_available.csv", available_fields, kept_available_rows)

        reports_path = src_dataset / "reports_raw.csv"
        if reports_path.exists():
            report_fields, report_rows = read_csv(reports_path)
            kept_report_rows = [row for row in report_rows if should_keep_report_row(src_dataset.name, row)]
            write_csv(dst_dataset / "reports_raw.csv", report_fields, kept_report_rows)

        dropped_samples = src_dataset / "dropped_samples.csv"
        if dropped_samples.exists():
            shutil.copy2(dropped_samples, dst_dataset / dropped_samples.name)

        link_modes = Counter()
        missing = []
        for row in kept_manifest_rows:
            rel = Path(row["bitstream_path"])
            src_bin = src_dataset / "bitstreams" / rel
            dst_bin = dst_dataset / "bitstreams" / rel
            if not src_bin.exists():
                missing.append(str(rel))
                continue
            link_modes[link_or_copy(src_bin, dst_bin)] += 1
        if missing:
            raise FileNotFoundError(f"{src_dataset.name}: missing referenced bitstreams: {missing[:5]}")

        raw_counts = Counter(row["class_label"] for row in kept_manifest_rows)
        effective_counts = Counter(
            row["class_label"]
            for row in kept_manifest_rows
            if row["class_label"] == "0" or int(float(row["ro_count"])) >= min_ro
        )
        summaries.append(
            {
                "dataset": src_dataset.name,
                "manifest_rows": len(kept_manifest_rows),
                "benign_rows": raw_counts.get("0", 0),
                "standalone_rows": raw_counts.get("1", 0),
                "effective_min_ro": min_ro,
                "effective_benign_rows": effective_counts.get("0", 0),
                "effective_standalone_rows": effective_counts.get("1", 0),
                "hardlinks": link_modes.get("hardlink", 0),
                "copies": link_modes.get("copy", 0),
            }
        )
    return summaries


def validate_balanced_vault(dest_vault: Path, min_ro: int) -> list[dict[str, Any]]:
    summaries = []
    for dataset in sorted(path for path in dest_vault.iterdir() if path.is_dir() and path.name.startswith("full_dataset_")):
        fields, rows = read_csv(dataset / "manifest.csv")
        del fields
        if dataset.name == "full_dataset_it2_2026-04-08":
            bad = [row for row in rows if row.get("class_label") == "1"]
            if bad:
                raise RuntimeError(f"{dataset}: found {len(bad)} standalone rows after filtering")
        missing = [
            row["bitstream_path"]
            for row in rows
            if not (dataset / "bitstreams" / row["bitstream_path"]).exists()
        ]
        if missing:
            raise FileNotFoundError(f"{dataset}: missing referenced bitstreams: {missing[:5]}")
        raw_counts = Counter(row["class_label"] for row in rows)
        effective_counts = Counter(
            row["class_label"]
            for row in rows
            if row["class_label"] == "0" or int(float(row["ro_count"])) >= min_ro
        )
        summaries.append(
            {
                "dataset": dataset.name,
                "manifest_rows": len(rows),
                "benign_rows": raw_counts.get("0", 0),
                "standalone_rows": raw_counts.get("1", 0),
                "effective_min_ro": min_ro,
                "effective_benign_rows": effective_counts.get("0", 0),
                "effective_standalone_rows": effective_counts.get("1", 0),
                "hardlinks": "",
                "copies": "",
            }
        )
    return summaries


def validate_existing_configs(config_dir: Path, dest_vault: Path) -> list[dict[str, str]]:
    import yaml

    rows = []
    paths = sorted(config_dir.glob("*.yaml"))
    if len(paths) != 6:
        raise RuntimeError(f"expected 6 generated configs in {config_dir}, found {len(paths)}")
    for path in paths:
        cfg = yaml.safe_load(path.read_text()) or {}
        train_vault_base = cfg.get("data", {}).get("train_vault_base")
        if str(train_vault_base) != str(dest_vault):
            raise RuntimeError(f"{path}: train_vault_base={train_vault_base!r}, expected {dest_vault}")
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
    dest_vault: Path,
    output_root: str,
    *,
    reuse_existing_configs: bool = False,
) -> list[dict[str, str]]:
    import yaml

    if config_dir.exists() and any(config_dir.glob("*.yaml")):
        if reuse_existing_configs:
            rows = validate_existing_configs(config_dir, dest_vault)
            write_csv(
                results_dir / "big_ro_balanced_config_manifest.csv",
                ["experiment_name", "phase", "config_path", "source_config"],
                rows,
            )
            return rows
        raise FileExistsError(f"config dir already contains YAML files: {config_dir}")
    config_dir.mkdir(parents=True, exist_ok=True)
    results_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, str]] = []
    for phase, sources in [("float", FLOAT_CONFIGS), ("qat_p50", QAT_CONFIGS)]:
        for name, source in sources.items():
            source = EXAMPLE_ROOT / source
            if not source.exists():
                raise FileNotFoundError(source)
            cfg = yaml.safe_load(source.read_text()) or {}
            cfg.setdefault("data", {})
            cfg["data"]["train_vault_base"] = str(dest_vault)
            cfg.setdefault("run", {})
            cfg["run"]["output_root"] = output_root
            cfg["run"]["timestamped_root"] = False
            cfg.setdefault("experiment", {})
            cfg["experiment"]["name"] = name
            cfg["experiment"]["phase"] = phase
            cfg["experiment"]["suite"] = "hls4ml_big_ro_balanced_training"
            cfg["experiment"]["tier"] = cfg["experiment"].get("tier") or "green"
            cfg["experiment"]["source_config"] = str(source)
            cfg["experiment"]["train_vault_base"] = str(dest_vault)
            cfg["experiment"]["qat_initialization"] = "scratch" if phase == "qat_p50" else ""
            out = config_dir / f"{name}.yaml"
            out.write_text(yaml.safe_dump(cfg, sort_keys=False))
            rows.append({"experiment_name": name, "phase": phase, "config_path": str(out), "source_config": str(source)})
    write_csv(
        results_dir / "big_ro_balanced_config_manifest.csv",
        ["experiment_name", "phase", "config_path", "source_config"],
        rows,
    )
    return rows


def main() -> None:
    args = parse_args()
    source_vault = args.source_vault.resolve()
    dest_vault = args.dest_vault.resolve()
    config_dir = (EXAMPLE_ROOT / args.config_dir).resolve() if not args.config_dir.is_absolute() else args.config_dir.resolve()
    results_dir = (EXAMPLE_ROOT / args.results_dir).resolve() if not args.results_dir.is_absolute() else args.results_dir.resolve()

    if args.reuse_existing_vault:
        if not dest_vault.is_dir():
            raise FileNotFoundError(f"cannot reuse missing vault: {dest_vault}")
        summaries = validate_balanced_vault(dest_vault, args.min_ro)
    else:
        summaries = create_balanced_vault(source_vault, dest_vault, args.min_ro)

    summary_fields = [
        "dataset",
        "manifest_rows",
        "benign_rows",
        "standalone_rows",
        "effective_min_ro",
        "effective_benign_rows",
        "effective_standalone_rows",
        "hardlinks",
        "copies",
    ]
    write_csv(results_dir / "big_ro_balanced_vault_summary.csv", summary_fields, summaries)
    config_rows = write_training_configs(
        config_dir,
        results_dir,
        dest_vault,
        args.output_root,
        reuse_existing_configs=args.reuse_existing_configs,
    )

    total = Counter()
    effective = Counter()
    for row in summaries:
        total["benign"] += int(row["benign_rows"])
        total["standalone"] += int(row["standalone_rows"])
        effective["benign"] += int(row["effective_benign_rows"])
        effective["standalone"] += int(row["effective_standalone_rows"])
    balanced_n = min(effective["benign"], effective["standalone"])
    print(f"[big-ro] vault={dest_vault}")
    print(f"[big-ro] raw_counts benign={total['benign']} standalone={total['standalone']}")
    print(
        f"[big-ro] effective_min_ro={args.min_ro} benign={effective['benign']} "
        f"standalone={effective['standalone']} balanced_each={balanced_n}"
    )
    print(f"[big-ro] configs={len(config_rows)} dir={config_dir}")
    print(f"[big-ro] results={results_dir}")


if __name__ == "__main__":
    main()
