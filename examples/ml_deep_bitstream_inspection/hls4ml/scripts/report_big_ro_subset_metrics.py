#!/usr/bin/env python3
"""Report final big-RO model metrics by dataset-origin subset."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed


SMALL_RO_PREFIXES = ("it1", "it2")
BIG_RO_PREFIXES = ("it4",)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts-root", type=Path, default=Path("artifacts_big_ro"))
    parser.add_argument(
        "--status-csv",
        type=Path,
        action="append",
        default=[
            Path("results/big_ro_training/suite_status.csv"),
            Path("results/big_ro_training_512_serial/suite_status.csv"),
        ],
        help="Suite status CSV to use for successful final QAT run discovery. May be repeated.",
    )
    parser.add_argument("--output-md", type=Path, default=Path("artifacts_big_ro/top_level_results.md"))
    parser.add_argument("--output-csv", type=Path, default=Path("artifacts_big_ro/top_level_results.csv"))
    return parser.parse_args()


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fieldnames is None:
        fieldnames = list(rows[0].keys()) if rows else []
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def to_int(value: Any) -> int | None:
    try:
        if value in ("", None):
            return None
        return int(float(value))
    except (TypeError, ValueError):
        return None


def to_float(value: Any) -> float | None:
    try:
        if value in ("", None):
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def class_label(row: dict[str, str]) -> int | None:
    value = to_int(row.get("class_label"))
    if value is not None:
        return value
    class_name = str(row.get("class_name", "")).strip().lower()
    if class_name == "standalone":
        return 1
    if class_name == "benign":
        return 0
    return None


def source_prefix(row: dict[str, str]) -> str:
    sample_id = str(row.get("sample_id", "")).strip()
    return sample_id.split("_", 1)[0] if "_" in sample_id else ""


def model_label(experiment_name: str) -> str:
    match = re.search(r"res(\d+)_layers(\d+)", experiment_name)
    if match:
        prefix = f"{match.group(1)}x{match.group(2)}"
    else:
        prefix = experiment_name
    if "W8A8" in experiment_name and "P50" in experiment_name:
        return f"{prefix} W8A8 P50"
    return prefix


def model_sort_key(run_root: Path) -> tuple[int, int, str]:
    match = re.search(r"res(\d+)_layers(\d+)", run_root.name)
    if not match:
        return (0, 0, run_root.name)
    return (int(match.group(1)), int(match.group(2)), run_root.name)


def discover_successful_qat_runs(status_csvs: list[Path], artifacts_root: Path) -> list[Path]:
    roots: list[Path] = []
    seen: set[Path] = set()
    for status_csv in status_csvs:
        if not status_csv.exists():
            continue
        for row in read_csv(status_csv):
            if row.get("status") != "success" or row.get("phase") != "qat_p50":
                continue
            run_root_value = row.get("run_root")
            if not run_root_value:
                continue
            run_root = Path(run_root_value)
            if not run_root.is_absolute():
                run_root = (status_csv.parent / run_root).resolve()
            if not (run_root / "pooled" / "per_sample.csv").exists():
                continue
            resolved = run_root.resolve()
            if resolved not in seen:
                seen.add(resolved)
                roots.append(resolved)

    if roots:
        return sorted(roots, key=model_sort_key)

    fallback = sorted(artifacts_root.glob("cnn_small_hls_opt_img*/notebook_pruned_qat/*W8A8*P50*/pooled/per_sample.csv"))
    return sorted((path.parents[1].resolve() for path in fallback), key=model_sort_key)


def subset_rows(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    benign = [row for row in rows if class_label(row) == 0]
    standalone = [row for row in rows if class_label(row) == 1]
    small = [row for row in standalone if source_prefix(row) in SMALL_RO_PREFIXES]
    big = [row for row in standalone if source_prefix(row) in BIG_RO_PREFIXES]
    unknown = [row for row in standalone if source_prefix(row) not in (*SMALL_RO_PREFIXES, *BIG_RO_PREFIXES)]
    if unknown:
        examples = ", ".join(str(row.get("sample_id", "")) for row in unknown[:5])
        raise ValueError(f"standalone rows with unknown dataset prefix: {examples}")
    return {
        "small_ro": [*benign, *small],
        "big_ro": [*benign, *big],
        "combined": rows,
    }


def metric_summary(rows: list[dict[str, str]], *, full_device_luts: float, ro_luts_per_ro: float) -> dict[str, Any]:
    tn = fp = fn = tp = 0
    losses: list[float] = []
    standalone_ro_counts: list[int] = []
    prefixes: set[str] = set()
    for row in rows:
        label = class_label(row)
        if label is None:
            raise ValueError(f"missing class label for sample {row.get('sample_id', '')}")
        prob = to_float(row.get("probability"))
        if prob is None:
            raise ValueError(f"missing probability for sample {row.get('sample_id', '')}")
        pred = 1 if prob >= 0.5 else 0
        if label == 0 and pred == 0:
            tn += 1
        elif label == 0 and pred == 1:
            fp += 1
        elif label == 1 and pred == 0:
            fn += 1
        elif label == 1 and pred == 1:
            tp += 1
        else:
            raise ValueError(f"unexpected label/pred pair for sample {row.get('sample_id', '')}")
        loss = to_float(row.get("per_sample_bce_loss"))
        if loss is not None:
            losses.append(loss)
        if label == 1:
            ro_count = to_int(row.get("ro_count"))
            if ro_count is not None:
                standalone_ro_counts.append(ro_count)
            prefixes.add(source_prefix(row))

    n = tn + fp + fn + tp
    accuracy = (tn + tp) / n if n else math.nan
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    specificity = tn / (tn + fp) if (tn + fp) else 0.0
    f1 = 2.0 * precision * recall / (precision + recall) if (precision + recall) else 0.0
    balanced_accuracy = (recall + specificity) / 2.0
    mcc_denom = math.sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn))
    mcc = ((tp * tn) - (fp * fn)) / mcc_denom if mcc_denom else 0.0

    if standalone_ro_counts:
        ro_min = min(standalone_ro_counts)
        ro_max = max(standalone_ro_counts)
        ro_pct_min = ro_min * ro_luts_per_ro / full_device_luts * 100.0
        ro_pct_max = ro_max * ro_luts_per_ro / full_device_luts * 100.0
    else:
        ro_min = ro_max = None
        ro_pct_min = ro_pct_max = None

    return {
        "n_samples": n,
        "n_benign": tn + fp,
        "n_standalone": tp + fn,
        "standalone_source_prefixes": ",".join(sorted(prefix for prefix in prefixes if prefix)),
        "standalone_ro_count_min": ro_min,
        "standalone_ro_count_max": ro_max,
        "standalone_ro_full_fpga_lut_percent_min": ro_pct_min,
        "standalone_ro_full_fpga_lut_percent_max": ro_pct_max,
        "bce_loss": sum(losses) / len(losses) if losses else None,
        "accuracy": accuracy,
        "balanced_accuracy": balanced_accuracy,
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "mcc": mcc,
        "confusion_matrix": [[tn, fp], [fn, tp]],
        "tn": tn,
        "fp": fp,
        "fn": fn,
        "tp": tp,
    }


def subset_label(subset: str) -> str:
    return {
        "small_ro": "Small RO (it1+it2 standalone)",
        "big_ro": "Big RO (it4 standalone)",
        "combined": "Combined",
    }[subset]


def subset_sort_order(subset: str) -> int:
    return {"small_ro": 0, "big_ro": 1, "combined": 2}.get(subset, 99)


def fmt_float(value: Any, digits: int = 4) -> str:
    if value is None:
        return ""
    try:
        value = float(value)
    except (TypeError, ValueError):
        return str(value)
    if math.isnan(value):
        return ""
    return f"{value:.{digits}f}"


def csv_metric_row(
    *,
    model: str,
    experiment_name: str,
    run_root: Path,
    subset: str,
    metrics: dict[str, Any],
) -> dict[str, Any]:
    return {
        "model": model,
        "experiment_name": experiment_name,
        "run_root": str(run_root),
        "subset": subset,
        "subset_label": subset_label(subset),
        "standalone_source_prefixes": metrics["standalone_source_prefixes"],
        "n_samples": metrics["n_samples"],
        "n_benign": metrics["n_benign"],
        "n_standalone": metrics["n_standalone"],
        "standalone_ro_count_min": metrics["standalone_ro_count_min"],
        "standalone_ro_count_max": metrics["standalone_ro_count_max"],
        "standalone_ro_full_fpga_lut_percent_min": fmt_float(
            metrics["standalone_ro_full_fpga_lut_percent_min"], 6
        ),
        "standalone_ro_full_fpga_lut_percent_max": fmt_float(
            metrics["standalone_ro_full_fpga_lut_percent_max"], 6
        ),
        "accuracy": fmt_float(metrics["accuracy"], 6),
        "f1": fmt_float(metrics["f1"], 6),
        "precision": fmt_float(metrics["precision"], 6),
        "recall": fmt_float(metrics["recall"], 6),
        "tpr": fmt_float(metrics["recall"], 6),
        "balanced_accuracy": fmt_float(metrics["balanced_accuracy"], 6),
        "tn": metrics["tn"],
        "fp": metrics["fp"],
        "fn": metrics["fn"],
        "tp": metrics["tp"],
    }


def write_top_level_markdown(path: Path, rows: list[dict[str, Any]]) -> None:
    lines = [
        "# Big-RO Final Pruned Model Results",
        "",
        "Subset metrics are computed from each final QAT P50 pooled fold output.",
        "Small-RO positives are standalone samples from `it1` and `it2`; big-RO positives are standalone samples from `it4`.",
        "All benign pooled samples are reused as the negative class for both subset evaluations so F1 and accuracy remain binary classification metrics.",
        "",
        "| Model | Subset | Benign n | Standalone n | RO count range | Full-FPGA RO LUT % range | Accuracy | F1 | Precision | Recall | TPR | TN | FP | FN | TP |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        ro_min = row.get("standalone_ro_count_min")
        ro_max = row.get("standalone_ro_count_max")
        ro_range = f"{ro_min}-{ro_max}" if ro_min not in ("", None) and ro_max not in ("", None) else ""
        pct_min = row.get("standalone_ro_full_fpga_lut_percent_min")
        pct_max = row.get("standalone_ro_full_fpga_lut_percent_max")
        pct_range = f"{pct_min}-{pct_max}" if pct_min and pct_max else ""
        lines.append(
            "| "
            + " | ".join(
                [
                    str(row["model"]),
                    str(row["subset_label"]),
                    str(row["n_benign"]),
                    str(row["n_standalone"]),
                    ro_range,
                    pct_range,
                    str(row["accuracy"]),
                    str(row["f1"]),
                    str(row["precision"]),
                    str(row["recall"]),
                    str(row["tpr"]),
                    str(row["tn"]),
                    str(row["fp"]),
                    str(row["fn"]),
                    str(row["tp"]),
                ]
            )
            + " |"
        )
    lines.extend(
        [
            "",
            "## Source Runs",
            "",
            "| Model | Run root |",
            "| --- | --- |",
        ]
    )
    seen: set[tuple[str, str]] = set()
    for row in rows:
        key = (str(row["model"]), str(row["run_root"]))
        if key in seen:
            continue
        seen.add(key)
        lines.append(f"| {row['model']} | `{row['run_root']}` |")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    from pipeline.device_resources import RO_LUTS_PER_STANDALONE_RO, XCU55C_TOTAL_CLB_LUTS

    artifacts_root = args.artifacts_root.resolve()
    run_roots = discover_successful_qat_runs(args.status_csv, artifacts_root)
    if not run_roots:
        raise SystemExit("no successful final QAT P50 run roots found")

    subset_definition = {
        "small_ro": {
            "positive_class": "standalone",
            "standalone_source_prefixes": list(SMALL_RO_PREFIXES),
            "negative_class": "all pooled benign samples",
        },
        "big_ro": {
            "positive_class": "standalone",
            "standalone_source_prefixes": list(BIG_RO_PREFIXES),
            "negative_class": "all pooled benign samples",
        },
        "combined": {
            "samples": "all pooled samples",
        },
        "ro_luts_per_ro": float(RO_LUTS_PER_STANDALONE_RO),
        "full_device_luts": float(XCU55C_TOTAL_CLB_LUTS),
    }
    fieldnames = [
        "model",
        "experiment_name",
        "run_root",
        "subset",
        "subset_label",
        "standalone_source_prefixes",
        "n_samples",
        "n_benign",
        "n_standalone",
        "standalone_ro_count_min",
        "standalone_ro_count_max",
        "standalone_ro_full_fpga_lut_percent_min",
        "standalone_ro_full_fpga_lut_percent_max",
        "accuracy",
        "f1",
        "precision",
        "recall",
        "tpr",
        "balanced_accuracy",
        "tn",
        "fp",
        "fn",
        "tp",
    ]
    top_level_rows: list[dict[str, Any]] = []
    for run_root in run_roots:
        per_sample_csv = run_root / "pooled" / "per_sample.csv"
        rows = read_csv(per_sample_csv)
        model = model_label(run_root.name)
        subset_metrics: dict[str, Any] = {}
        pooled_csv_rows: list[dict[str, Any]] = []
        for subset, selected_rows in subset_rows(rows).items():
            metrics = metric_summary(
                selected_rows,
                full_device_luts=float(XCU55C_TOTAL_CLB_LUTS),
                ro_luts_per_ro=float(RO_LUTS_PER_STANDALONE_RO),
            )
            subset_metrics[subset] = metrics
            csv_row = csv_metric_row(
                model=model,
                experiment_name=run_root.name,
                run_root=run_root,
                subset=subset,
                metrics=metrics,
            )
            pooled_csv_rows.append(csv_row)
            top_level_rows.append(csv_row)

        pooled_dir = run_root / "pooled"
        write_json(
            pooled_dir / "metrics_by_dataset_subset.json",
            {
                "model": model,
                "experiment_name": run_root.name,
                "run_root": str(run_root),
                "subset_definition": subset_definition,
                "subsets": subset_metrics,
            },
        )
        write_csv(pooled_dir / "metrics_by_dataset_subset.csv", pooled_csv_rows, fieldnames)
        print(f"[subset-metrics] wrote {pooled_dir / 'metrics_by_dataset_subset.json'}")
        print(f"[subset-metrics] wrote {pooled_dir / 'metrics_by_dataset_subset.csv'}")

    top_level_rows.sort(
        key=lambda row: (*model_sort_key(Path(str(row["run_root"]))), subset_sort_order(str(row["subset"])))
    )
    write_csv(args.output_csv, top_level_rows, fieldnames)
    write_top_level_markdown(args.output_md, top_level_rows)
    print(f"[subset-metrics] wrote {args.output_csv}")
    print(f"[subset-metrics] wrote {args.output_md}")


if __name__ == "__main__":
    main()
