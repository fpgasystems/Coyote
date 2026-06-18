#!/usr/bin/env python3
"""Prepare, track, and stage pending configs for the expansion sweep."""

from __future__ import annotations

import argparse
import shutil
import sys
import time
from pathlib import Path
from typing import Any, Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.experiment_cli import reexec_local_python_if_needed
from pipeline.experiment_suite import (
    feasibility_row,
    generate_phase123,
    generate_phase4,
    generate_phase45,
    generate_phase5,
    load_generated_configs,
    load_yaml,
    read_csv,
    write_csv,
    write_generation_outputs,
)


TARGETS = [(512, 5), (512, 6), (512, 7), (1024, 5), (1024, 6), (1024, 7)]
QUANT_BITS = [4, 6, 8]
PRUNE_BITS = [6, 8]
PRUNE_TARGETS = [25, 50, 75]
RF_VALUES = [1, 2, 4, 8, 16, 32]
RF_PRUNE_TARGET = 50
DOC_PATH = Path("AGENT_EXPAND_SWEEP.md")


def experiment_name(resolution: int, layers: int, weight: str, activation: str, pruning: str, rf: str) -> str:
    return f"res{resolution}_layers{layers}_W{weight}A{activation}_P{pruning}_RF{rf}"


def baseline_name(resolution: int, layers: int) -> str:
    return experiment_name(resolution, layers, "float", "float", "0", "base")


def quant_name(resolution: int, layers: int, bits: int) -> str:
    return experiment_name(resolution, layers, str(bits), str(bits), "0", "base")


def prune_name(resolution: int, layers: int, bits: int, target: int) -> str:
    return experiment_name(resolution, layers, str(bits), str(bits), str(target), "base")


def rf_name(resolution: int, layers: int, bits: int, reuse_factor: int) -> str:
    return experiment_name(resolution, layers, str(bits), str(bits), str(RF_PRUNE_TARGET), str(reuse_factor))


def rows_by_name(path: Path) -> dict[str, dict[str, str]]:
    return {row.get("experiment_name", ""): row for row in read_csv(path)}


def read_statuses(results_dir: Path) -> dict[str, dict[str, str]]:
    rows = read_csv(results_dir / "suite_status.csv")
    out: dict[str, dict[str, str]] = {}
    for row in rows:
        name = row.get("experiment_name", "")
        if not name:
            continue
        old = out.get(name)
        if old is None or row.get("status") == "success":
            out[name] = row
    return out


def successful_names(global_summary: dict[str, dict[str, str]], local_status: dict[str, dict[str, str]]) -> set[str]:
    names = {name for name, row in global_summary.items() if row.get("status") == "success"}
    names.update(name for name, row in local_status.items() if row.get("status") == "success")
    return names


def status_for(name: str, global_summary: dict[str, dict[str, str]], local_status: dict[str, dict[str, str]]) -> str:
    local = local_status.get(name)
    if local:
        status = local.get("status") or "not_run"
        if status == "failed":
            return f"failed:{local.get('failure_stage', '') or 'unknown'}"
        return status
    global_row = global_summary.get(name)
    if global_row:
        status = global_row.get("status") or "not_run"
        if status == "failed":
            return f"failed:{global_row.get('failure_stage', '') or 'unknown'}"
        return status
    return "not_run"


def fresh_yaml_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for old in path.glob("*.yaml"):
        old.unlink()


def copy_pending_configs(configs_dir: Path, pending_dir: Path, names: Iterable[str], done: set[str]) -> list[str]:
    fresh_yaml_dir(pending_dir)
    pending: list[str] = []
    for name in sorted(set(names)):
        if name in done:
            continue
        src = configs_dir / f"{name}.yaml"
        if not src.exists():
            continue
        shutil.copy2(src, pending_dir / src.name)
        pending.append(name)
    return pending


def all_feasibility_rows(configs_dir: Path) -> list[dict[str, Any]]:
    rows = [feasibility_row(cfg, path) for path, cfg in load_generated_configs(configs_dir)]
    rows.sort(
        key=lambda row: (
            str(row.get("phase", "")),
            int(row.get("input_resolution") or 0),
            int(row.get("num_layers") or 0),
            str(row.get("experiment_name", "")),
        )
    )
    return rows


def selected_rows_for_names(configs_dir: Path, names: Iterable[str], status_sources: dict[str, dict[str, str]] | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    status_sources = status_sources or {}
    for name in names:
        cfg = configs_dir / f"{name}.yaml"
        if not cfg.exists():
            continue
        row: dict[str, Any] = {
            "experiment_name": name,
            "config_path": str(cfg),
        }
        source = status_sources.get(name)
        if source:
            row["run_root"] = source.get("run_root", "")
            row["hls_sweep_root"] = source.get("hls_sweep_root", "")
        rows.append(row)
    return rows


def existing_success_row(name: str, args: argparse.Namespace) -> dict[str, str] | None:
    local = read_statuses(args.results_dir).get(name)
    if local and local.get("status") == "success" and local.get("run_root"):
        return local
    summary = rows_by_name(args.global_results / "experiment_summary.csv")
    row = summary.get(name)
    if row and row.get("status") == "success" and row.get("run_root") and Path(row.get("config_path", "")).exists():
        return row
    return None


def generate_base_configs(args: argparse.Namespace) -> None:
    args.configs_dir.mkdir(parents=True, exist_ok=True)
    args.results_dir.mkdir(parents=True, exist_ok=True)
    suite = load_yaml(args.suite)
    baseline_rows = generate_phase123(suite, args.configs_dir)
    baseline_selected = selected_rows_for_names(args.configs_dir, [baseline_name(*target) for target in TARGETS])
    phase4_rows = generate_phase4(suite, args.configs_dir, baseline_selected)
    prune_selected = selected_rows_for_names(
        args.configs_dir,
        [quant_name(resolution, layers, bits) for resolution, layers in TARGETS for bits in PRUNE_BITS],
    )
    phase45_rows = generate_phase45(suite, args.configs_dir, prune_selected)
    write_generation_outputs(baseline_rows + phase4_rows + phase45_rows, args.results_dir)


def prepare(args: argparse.Namespace) -> None:
    generate_base_configs(args)
    global_summary = rows_by_name(args.global_results / "experiment_summary.csv")
    local_status = read_statuses(args.results_dir)
    done = successful_names(global_summary, local_status)

    phase4_all = [quant_name(resolution, layers, bits) for resolution, layers in TARGETS for bits in QUANT_BITS]
    phase4_pending = copy_pending_configs(args.configs_dir, args.pending_dir / "phase4", phase4_all, done)

    quant_done = done | (set(phase4_all) - set(phase4_pending))
    phase45_all = [
        prune_name(resolution, layers, bits, target)
        for resolution, layers in TARGETS
        for bits in PRUNE_BITS
        for target in PRUNE_TARGETS
        if quant_name(resolution, layers, bits) in quant_done
    ]
    phase45_pending = copy_pending_configs(args.configs_dir, args.pending_dir / "phase45", phase45_all, done)

    phase5_all = [rf_name(resolution, layers, bits, rf) for resolution, layers in TARGETS for bits in PRUNE_BITS for rf in RF_VALUES]
    manifest = write_manifest(args, phase4_all, phase45_all, phase5_all)
    write_pending_manifest(args.results_dir / "pending_phase4.csv", phase4_pending)
    write_pending_manifest(args.results_dir / "pending_phase45.csv", phase45_pending)
    write_doc(args, phase4_all, phase45_all, phase5_all, phase4_pending, phase45_pending, [], manifest)
    print(f"[expand] configs={args.configs_dir}")
    print(f"[expand] pending phase4={len(phase4_pending)} phase45={len(phase45_pending)}")
    print(f"[expand] doc={DOC_PATH}")


def generate_phase5_configs(args: argparse.Namespace) -> None:
    generate_base_configs(args)
    selected: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    status_sources: dict[str, dict[str, str]] = {}
    for resolution, layers in TARGETS:
        for bits in PRUNE_BITS:
            source_name = prune_name(resolution, layers, bits, RF_PRUNE_TARGET)
            source = existing_success_row(source_name, args)
            if source:
                status_sources[source_name] = source
                cfg_path = Path(source.get("config_path", ""))
                selected.append(
                    {
                        "experiment_name": source_name,
                        "status": "success",
                        "run_root": source.get("run_root", ""),
                        "hls_sweep_root": source.get("hls_sweep_root", ""),
                        "config_path": str(cfg_path if cfg_path.exists() else args.configs_dir / f"{source_name}.yaml"),
                    }
                )
            else:
                missing.append({"experiment_name": source_name, "reason": "missing successful P50 pruning root"})

    write_csv(args.results_dir / "phase5_p50_selected.csv", selected)
    write_csv(args.results_dir / "phase5_missing_sources.csv", missing, fieldnames=["experiment_name", "reason"])
    phase5_rows: list[dict[str, Any]] = []
    if selected:
        suite = load_yaml(args.suite)
        phase5_rows = generate_phase5(suite, args.configs_dir, selected)
    all_rows = all_feasibility_rows(args.configs_dir)
    write_generation_outputs(all_rows, args.results_dir)

    global_summary = rows_by_name(args.global_results / "experiment_summary.csv")
    local_status = read_statuses(args.results_dir)
    done = successful_names(global_summary, local_status)
    phase4_all = [quant_name(resolution, layers, bits) for resolution, layers in TARGETS for bits in QUANT_BITS]
    phase45_all = [
        prune_name(resolution, layers, bits, target)
        for resolution, layers in TARGETS
        for bits in PRUNE_BITS
        for target in PRUNE_TARGETS
    ]
    phase5_all = [str(row["experiment_name"]) for row in phase5_rows]
    phase5_pending = copy_pending_configs(args.configs_dir, args.pending_dir / "phase5", phase5_all, done)
    write_pending_manifest(args.results_dir / "pending_phase5.csv", phase5_pending)
    phase5_expected = [rf_name(resolution, layers, bits, rf) for resolution, layers in TARGETS for bits in PRUNE_BITS for rf in RF_VALUES]
    manifest = write_manifest(args, phase4_all, phase45_all, phase5_expected)
    write_doc(args, phase4_all, phase45_all, phase5_expected, [], [], phase5_pending, manifest)
    print(f"[expand] generated phase5={len(phase5_rows)} selected_sources={len(selected)} pending={len(phase5_pending)}")


def write_pending_manifest(path: Path, names: list[str]) -> None:
    write_csv(path, [{"experiment_name": name} for name in names], fieldnames=["experiment_name"])


def write_manifest(args: argparse.Namespace, phase4_all: list[str], phase45_all: list[str], phase5_all: list[str]) -> list[dict[str, Any]]:
    global_summary = rows_by_name(args.global_results / "experiment_summary.csv")
    local_status = read_statuses(args.results_dir)
    rows: list[dict[str, Any]] = []
    for resolution, layers in TARGETS:
        for name, phase, setting in (
            [(baseline_name(resolution, layers), "1/2", "float")]
            + [(quant_name(resolution, layers, bits), "4", f"W{bits}A{bits}") for bits in QUANT_BITS]
            + [
                (prune_name(resolution, layers, bits, target), "4.5", f"W{bits}A{bits} P{target}")
                for bits in PRUNE_BITS
                for target in PRUNE_TARGETS
            ]
            + [(rf_name(resolution, layers, bits, rf), "5", f"W{bits}A{bits} P50 RF{rf}") for bits in PRUNE_BITS for rf in RF_VALUES]
        ):
            rows.append(
                {
                    "candidate": f"{resolution}x{layers}",
                    "experiment_name": name,
                    "phase": phase,
                    "setting": setting,
                    "status": status_for(name, global_summary, local_status),
                    "config_path": str(args.configs_dir / f"{name}.yaml") if (args.configs_dir / f"{name}.yaml").exists() else "",
                }
            )
    write_csv(args.results_dir / "expand_sweep_manifest.csv", rows)
    return rows


def count_status(names: list[str], global_summary: dict[str, dict[str, str]], local_status: dict[str, dict[str, str]]) -> tuple[int, int, int, int]:
    success = running = failed = not_run = 0
    for name in names:
        status = status_for(name, global_summary, local_status)
        if status == "success":
            success += 1
        elif status == "running":
            running += 1
        elif status.startswith("failed"):
            failed += 1
        elif status in {"not_run", ""}:
            not_run += 1
    return success, running, failed, not_run


def write_doc(
    args: argparse.Namespace,
    phase4_all: list[str],
    phase45_all: list[str],
    phase5_all: list[str],
    phase4_pending: list[str],
    phase45_pending: list[str],
    phase5_pending: list[str],
    manifest: list[dict[str, Any]],
) -> None:
    global_summary = rows_by_name(args.global_results / "experiment_summary.csv")
    local_status = read_statuses(args.results_dir)
    p4 = count_status(phase4_all, global_summary, local_status)
    p45 = count_status(phase45_all, global_summary, local_status)
    p5 = count_status(phase5_all, global_summary, local_status) if phase5_all else (0, 0, 0, 0)
    lines = [
        "# Expansion Sweep",
        "",
        f"Last updated: {time.strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## Scope",
        "",
        "- Configurations: `512x5`, `512x6`, `512x7`, `1024x5`, `1024x6`, `1024x7`.",
        "- `1204x5` is treated as `1024x5`.",
        "- Quantization: `W4A4`, `W6A6`, `W8A8`.",
        "- Pruning: `W6A6` and `W8A8` at `P25`, `P50`, `P75`.",
        "- Reuse-factor sweep: `W6A6/P50` and `W8A8/P50` at `RF1,RF2,RF4,RF8,RF16,RF32`.",
        "- HLS only after training; no bitstream, deploy, or validate stages.",
        "",
        "## Paths",
        "",
        f"- Suite: `{args.suite}`",
        f"- Configs: `{args.configs_dir}`",
        f"- Pending configs: `{args.pending_dir}`",
        f"- Results: `{args.results_dir}`",
        f"- Artifacts: `artifacts_expand_sweep`",
        "",
        "## Phase Progress",
        "",
        "| Phase | Scope | Success | Running | Failed | Not run | Pending configs |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
        f"| 4 | W4/W6/W8 P0 | {p4[0]} | {p4[1]} | {p4[2]} | {p4[3]} | {len(phase4_pending)} |",
        f"| 4.5 | W6/W8 P25/P50/P75 | {p45[0]} | {p45[1]} | {p45[2]} | {p45[3]} | {len(phase45_pending)} |",
        f"| 5 | W6/W8 P50 RF sweep | {p5[0]} | {p5[1]} | {p5[2]} | {p5[3]} | {len(phase5_pending)} |",
        "",
        "## Candidate Snapshot",
        "",
        "| Candidate | Phase 4 | Phase 4.5 | Phase 5 |",
        "| --- | ---: | ---: | ---: |",
    ]
    by_candidate: dict[str, list[dict[str, Any]]] = {}
    for row in manifest:
        by_candidate.setdefault(str(row["candidate"]), []).append(row)
    for candidate in [f"{resolution}x{layers}" for resolution, layers in TARGETS]:
        rows = by_candidate.get(candidate, [])
        phase_counts = {}
        for phase in ["4", "4.5", "5"]:
            phase_rows = [row for row in rows if row.get("phase") == phase]
            phase_counts[phase] = sum(1 for row in phase_rows if row.get("status") == "success")
        p4_total = len([row for row in rows if row.get("phase") == "4"])
        p45_total = len([row for row in rows if row.get("phase") == "4.5"])
        p5_total = len([row for row in rows if row.get("phase") == "5"])
        lines.append(
            f"| `{candidate}` | {phase_counts.get('4', 0)}/{p4_total} | "
            f"{phase_counts.get('4.5', 0)}/{p45_total} | {phase_counts.get('5', 0)}/{p5_total} |"
        )
    lines.append("")
    lines.append("## Remaining Work")
    lines.append("")
    remaining = [
        row for row in manifest if row.get("phase") in {"4", "4.5", "5"} and row.get("status") != "success"
    ]
    if not remaining:
        lines.append("All tracked expansion rows are successful.")
    else:
        lines.extend(["| Phase | Experiment | Status |", "| --- | --- | --- |"])
        for row in remaining[:80]:
            lines.append(f"| {row['phase']} | `{row['experiment_name']}` | {row['status']} |")
        if len(remaining) > 80:
            lines.append(f"| ... | {len(remaining) - 80} additional rows omitted | ... |")
    DOC_PATH.write_text("\n".join(line for line in lines if line is not None) + "\n")


def update_doc(args: argparse.Namespace) -> None:
    phase4_all = [quant_name(resolution, layers, bits) for resolution, layers in TARGETS for bits in QUANT_BITS]
    phase45_all = [
        prune_name(resolution, layers, bits, target)
        for resolution, layers in TARGETS
        for bits in PRUNE_BITS
        for target in PRUNE_TARGETS
    ]
    phase5_all = [rf_name(resolution, layers, bits, rf) for resolution, layers in TARGETS for bits in PRUNE_BITS for rf in RF_VALUES]
    phase4_pending = [row.get("experiment_name", "") for row in read_csv(args.results_dir / "pending_phase4.csv")]
    phase45_pending = [row.get("experiment_name", "") for row in read_csv(args.results_dir / "pending_phase45.csv")]
    phase5_pending = [row.get("experiment_name", "") for row in read_csv(args.results_dir / "pending_phase5.csv")]
    manifest = write_manifest(args, phase4_all, phase45_all, phase5_all)
    write_doc(args, phase4_all, phase45_all, phase5_all, phase4_pending, phase45_pending, phase5_pending, manifest)
    print(f"[expand] updated {DOC_PATH}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "phase5", "update-doc"])
    parser.add_argument("--suite", type=Path, default=Path("configs/hls4ml_expand_sweep_suite.yaml"))
    parser.add_argument("--configs-dir", type=Path, default=Path("configs/hls4ml_expand_sweep"))
    parser.add_argument("--pending-dir", type=Path, default=Path("configs/hls4ml_expand_sweep_pending"))
    parser.add_argument("--results-dir", type=Path, default=Path("results/expand_sweep"))
    parser.add_argument("--global-results", type=Path, default=Path("results"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed(EXAMPLE_ROOT)
    if args.action == "prepare":
        prepare(args)
    elif args.action == "phase5":
        generate_phase5_configs(args)
    elif args.action == "update-doc":
        update_doc(args)


if __name__ == "__main__":
    main()
