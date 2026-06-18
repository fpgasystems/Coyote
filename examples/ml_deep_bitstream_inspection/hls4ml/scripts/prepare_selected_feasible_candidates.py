#!/usr/bin/env python3
"""Prepare and report the selected feasible W8A8/P50 reuse-factor experiment."""

from __future__ import annotations

import argparse
import csv
import sys
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import (
    feasibility_row,
    generate_phase4,
    generate_phase45,
    generate_phase5,
    load_generated_configs,
    load_yaml,
    metadata_for_config,
    read_csv,
    write_csv,
    write_generation_outputs,
)


TARGETS = [
    (128, 6),
    (256, 6),
    (256, 7),
    (512, 7),
]
REUSE_FACTORS = [1, 2, 4, 8, 16, 32]
MARKER_START = "<!-- selected_feasible_candidates:start -->"
MARKER_END = "<!-- selected_feasible_candidates:end -->"


def experiment_name(resolution: int, layers: int, weight: str, activation: str, pruning: str, rf: str) -> str:
    return f"res{resolution}_layers{layers}_W{weight}A{activation}_P{pruning}_RF{rf}"


def csv_rows(path: Path) -> list[dict[str, str]]:
    return read_csv(path)


def write_rows(path: Path, rows: list[dict[str, Any]], fieldnames: list[str] | None = None) -> None:
    write_csv(path, rows, fieldnames=fieldnames)


def rows_by_name(path: Path) -> dict[str, dict[str, str]]:
    return {row.get("experiment_name", ""): row for row in csv_rows(path)}


def require_global_row(summary: dict[str, dict[str, str]], name: str) -> dict[str, str]:
    row = summary.get(name)
    if not row:
        raise SystemExit(f"missing source row in results/experiment_summary.csv: {name}")
    if row.get("status") != "success":
        raise SystemExit(f"source row is not successful: {name} status={row.get('status')}")
    config_path = Path(row.get("config_path", ""))
    if not config_path.exists():
        raise SystemExit(f"source config does not exist for {name}: {config_path}")
    return row


def target_float_name(resolution: int, layers: int) -> str:
    return experiment_name(resolution, layers, "float", "float", "0", "base")


def target_w8_name(resolution: int, layers: int) -> str:
    return experiment_name(resolution, layers, "8", "8", "0", "base")


def target_p50_name(resolution: int, layers: int) -> str:
    return experiment_name(resolution, layers, "8", "8", "50", "base")


def target_rf_name(resolution: int, layers: int, reuse_factor: int) -> str:
    return experiment_name(resolution, layers, "8", "8", "50", str(reuse_factor))


def all_feasibility_rows(config_dir: Path) -> list[dict[str, Any]]:
    rows = [feasibility_row(cfg, path) for path, cfg in load_generated_configs(config_dir)]
    rows.sort(key=lambda row: (str(row.get("phase")), int(row.get("input_resolution") or 0), int(row.get("num_layers") or 0), str(row.get("experiment_name"))))
    return rows


def write_manifest(results_dir: Path, summary: dict[str, dict[str, str]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for resolution, layers in TARGETS:
        source_name = target_float_name(resolution, layers)
        source = require_global_row(summary, source_name)
        rows.append(
            {
                "candidate": f"res{resolution}_layers{layers}",
                "input_resolution": resolution,
                "num_layers": layers,
                "source_experiment": source_name,
                "source_status": source.get("status", ""),
                "source_config_path": source.get("config_path", ""),
                "source_run_root": source.get("run_root", ""),
                "source_hls_sweep_root": source.get("hls_sweep_root", ""),
                "target_quantization": "W8A8",
                "target_pruning": "P50",
                "target_base_experiment": target_p50_name(resolution, layers),
                "reuse_factors": ",".join(str(value) for value in REUSE_FACTORS),
            }
        )
    write_rows(results_dir / "selected_candidates_manifest.csv", rows)
    lines = [
        "# Selected Feasible Candidates",
        "",
        "Targets use 8-bit weights/activations, 50% weight pruning, and RF values `1,2,4,8,16,32`.",
        "",
        "| Candidate | Source experiment | Source status | Target base | RF values |",
        "| --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['candidate']}` | `{row['source_experiment']}` | {row['source_status']} | "
            f"`{row['target_base_experiment']}` | `{row['reuse_factors']}` |"
        )
    (results_dir / "selected_candidates_manifest.md").write_text("\n".join(lines) + "\n")
    return rows


def prepare(args: argparse.Namespace) -> None:
    args.results_dir.mkdir(parents=True, exist_ok=True)
    args.configs_dir.mkdir(parents=True, exist_ok=True)
    summary = rows_by_name(args.global_results / "experiment_summary.csv")
    write_manifest(args.results_dir, summary)

    float_selected: list[dict[str, Any]] = []
    for resolution, layers in TARGETS:
        row = require_global_row(summary, target_float_name(resolution, layers))
        float_selected.append(row)
    write_rows(args.results_dir / "phase4_float_selected.csv", float_selected)

    suite = load_yaml(args.suite)
    phase4_rows = generate_phase4(suite, args.configs_dir, float_selected)
    w8_selected: list[dict[str, Any]] = []
    for resolution, layers in TARGETS:
        w8_name = target_w8_name(resolution, layers)
        w8_selected.append(
            {
                "experiment_name": w8_name,
                "config_path": str(args.configs_dir / f"{w8_name}.yaml"),
            }
        )
    write_rows(args.results_dir / "phase4_w8_selected.csv", w8_selected)
    phase45_rows = generate_phase45(suite, args.configs_dir, w8_selected)
    write_generation_outputs(phase4_rows + phase45_rows, args.results_dir)
    seed_phase4_cache(args)
    print(f"[selected] manifest={args.results_dir / 'selected_candidates_manifest.csv'}")
    print(f"[selected] generated phase4={len(phase4_rows)} phase45={len(phase45_rows)} configs={args.configs_dir}")


def seed_phase4_cache(args: argparse.Namespace) -> None:
    global_status = rows_by_name(args.global_results / "suite_status.csv")
    selected_status_path = args.results_dir / "suite_status.csv"
    selected_rows = csv_rows(selected_status_path)
    by_key = {(row.get("experiment_name", ""), row.get("requested_stages", "")): row for row in selected_rows}
    seeded = []
    for resolution, layers in TARGETS:
        name = target_w8_name(resolution, layers)
        source = global_status.get(name)
        if not source or source.get("status") != "success":
            continue
        row = dict(source)
        row["config_path"] = str(args.configs_dir / f"{name}.yaml")
        key = (row.get("experiment_name", ""), row.get("requested_stages", ""))
        by_key[key] = row
        seeded.append(name)
    out = sorted(by_key.values(), key=lambda row: (row.get("phase", ""), row.get("experiment_name", ""), row.get("requested_stages", "")))
    if out:
        write_rows(selected_status_path, out)
    print(f"[selected] seeded cached phase4 rows: {', '.join(seeded) if seeded else 'none'}")


def generate_phase5_configs(args: argparse.Namespace) -> None:
    statuses = rows_by_name(args.results_dir / "suite_status.csv")
    selected: list[dict[str, Any]] = []
    missing: list[str] = []
    for resolution, layers in TARGETS:
        name = target_p50_name(resolution, layers)
        status = statuses.get(name)
        config_path = args.configs_dir / f"{name}.yaml"
        if not status or status.get("status") != "success":
            missing.append(f"{name}: {status.get('status') if status else 'not_run'}")
            continue
        selected.append(
            {
                "experiment_name": name,
                "status": status.get("status", ""),
                "run_root": status.get("run_root", ""),
                "hls_sweep_root": status.get("hls_sweep_root", ""),
                "config_path": str(config_path),
            }
        )
    write_rows(args.results_dir / "phase45_p50_selected.csv", selected)
    if missing:
        (args.results_dir / "phase5_missing_sources.txt").write_text("\n".join(missing) + "\n")
        print("[selected] missing phase5 sources:")
        for item in missing:
            print(f"  - {item}")
    if not selected:
        raise SystemExit("no successful W8A8_P50 rows available for phase5 generation")
    suite = load_yaml(args.suite)
    phase5_rows = generate_phase5(suite, args.configs_dir, selected)
    write_generation_outputs(all_feasibility_rows(args.configs_dir), args.results_dir)
    print(f"[selected] generated phase5={len(phase5_rows)} configs from selected={len(selected)}")


def status_for_name(statuses: dict[str, dict[str, str]], name: str) -> str:
    row = statuses.get(name)
    if not row:
        return "not_run"
    status = row.get("status", "") or "not_run"
    if status == "failed":
        return f"failed ({row.get('failure_stage', 'unknown')})"
    return status


def next_action_for_status(status: str, scheduled_action: str, rerun_action: str) -> str:
    if status == "running":
        return "Wait for current run to finish"
    if status == "not_run":
        return scheduled_action
    if status.startswith("failed"):
        return rerun_action
    return scheduled_action


def update_finish_doc(args: argparse.Namespace) -> None:
    statuses = rows_by_name(args.results_dir / "suite_status.csv")
    summary_rows = csv_rows(args.results_dir / "experiment_summary.csv")
    status_counts: dict[str, int] = {}
    for row in summary_rows:
        status_counts[row.get("status", "not_run")] = status_counts.get(row.get("status", "not_run"), 0) + 1

    lines = [
        MARKER_START,
        "## Selected Feasible Candidate RF Sweep",
        "",
        f"Last updated: `{time.strftime('%Y-%m-%d %H:%M:%S')}`.",
        "",
        "- Results: `results/selected_feasible_candidates/`",
        "- Configs: `configs/hls4ml_selected_feasible_candidates/`",
        "- Artifacts: `artifacts_selected_feasible_candidates/`",
        "- Target: `W8A8`, `P50`, RF values `1,2,4,8,16,32`.",
        f"- Summary rows: `{len(summary_rows)}`; status counts: `{status_counts}`.",
        "",
        "| Candidate | W8 base | P50 base | RF rows complete |",
        "| --- | --- | --- | --- |",
    ]
    for resolution, layers in TARGETS:
        rf_names = [target_rf_name(resolution, layers, value) for value in REUSE_FACTORS]
        rf_done = sum(1 for name in rf_names if statuses.get(name, {}).get("status") == "success")
        lines.append(
            f"| `res{resolution}_layers{layers}` | {status_for_name(statuses, target_w8_name(resolution, layers))} | "
            f"{status_for_name(statuses, target_p50_name(resolution, layers))} | {rf_done}/{len(REUSE_FACTORS)} |"
        )
    lines.extend(
        [
            "",
            "## Selected Feasible Experiments Still To Run",
            "",
            "| Priority | Experiment(s) | Current state | Suggested next action |",
            "| --- | --- | --- | --- |",
        ]
    )
    remaining = []
    for resolution, layers in TARGETS:
        w8 = target_w8_name(resolution, layers)
        p50 = target_p50_name(resolution, layers)
        w8_status = status_for_name(statuses, w8)
        p50_status = status_for_name(statuses, p50)
        if statuses.get(w8, {}).get("status") != "success":
            remaining.append(
                (
                    "High",
                    w8,
                    w8_status,
                    next_action_for_status(w8_status, "Scheduled in current supervisor", "Rerun Phase 4 W8 base"),
                )
            )
        if statuses.get(p50, {}).get("status") != "success":
            remaining.append(
                (
                    "High",
                    p50,
                    p50_status,
                    next_action_for_status(p50_status, "Scheduled after Phase 4 completes", "Rerun Phase 4.5 W8/P50 base"),
                )
            )
        missing_rf = [target_rf_name(resolution, layers, value) for value in REUSE_FACTORS if statuses.get(target_rf_name(resolution, layers, value), {}).get("status") != "success"]
        if missing_rf:
            remaining.append(
                (
                    "High",
                    f"`res{resolution}_layers{layers}_W8A8_P50_RF{{{','.join(str(v) for v in REUSE_FACTORS)}}}`",
                    f"{len(missing_rf)} RF rows incomplete",
                    "Scheduled after successful P50 base",
                )
            )
    if remaining:
        for priority, experiments, state, action in remaining:
            exp_cell = experiments if str(experiments).startswith("`") else f"`{experiments}`"
            lines.append(f"| {priority} | {exp_cell} | {state} | {action} |")
    else:
        lines.append("| None | None | Complete | No selected-feasible follow-up required |")
    lines.append(MARKER_END)
    block = "\n".join(lines) + "\n"

    text = args.finish_doc.read_text() if args.finish_doc.exists() else ""
    if MARKER_START in text and MARKER_END in text:
        before = text.split(MARKER_START, 1)[0].rstrip()
        after = text.split(MARKER_END, 1)[1].strip()
        text = before + ("\n\n" + after if after else "")
    text = text.rstrip() + "\n\n" + block
    args.finish_doc.write_text(text)
    print(f"[selected] updated {args.finish_doc}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "seed-phase4-cache", "generate-phase5", "update-finish-doc"])
    parser.add_argument("--suite", type=Path, default=Path("configs/hls4ml_selected_feasible_candidates_suite.yaml"))
    parser.add_argument("--configs-dir", type=Path, default=Path("configs/hls4ml_selected_feasible_candidates"))
    parser.add_argument("--results-dir", type=Path, default=Path("results/selected_feasible_candidates"))
    parser.add_argument("--global-results", type=Path, default=Path("results"))
    parser.add_argument("--finish-doc", type=Path, default=Path("AGENT_EXPERIMENT_FINISH.md"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    if args.command == "prepare":
        prepare(args)
    elif args.command == "seed-phase4-cache":
        seed_phase4_cache(args)
    elif args.command == "generate-phase5":
        generate_phase5_configs(args)
    elif args.command == "update-finish-doc":
        update_finish_doc(args)


if __name__ == "__main__":
    main()
