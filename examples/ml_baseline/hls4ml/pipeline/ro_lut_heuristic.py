"""Manifest-derived RO LUT heuristic helpers."""

from __future__ import annotations

import csv
import re
from dataclasses import dataclass
from pathlib import Path
from statistics import mean
from typing import Any, Sequence


DEFAULT_VAULT_BASE = Path("/home/sdeheredia/coyote_vault_work")


@dataclass(frozen=True)
class RoLutHeuristic:
    min_ro: int
    max_ro: int
    min_lut_mean: float
    max_lut_mean: float
    luts_per_ro: float
    fixed_overhead_luts: float
    min_count: int
    max_count: int

    @property
    def title_fragment(self) -> str:
        return f"rough endpoint heuristic: {self.luts_per_ro:.3f} LUTs/RO"


def _to_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _to_int(value: Any) -> int | None:
    float_value = _to_float(value)
    if float_value is None:
        return None
    return int(float_value)


def discover_manifest_paths(vault_base: Path | str | None = None) -> list[tuple[str, Path]]:
    base = Path(vault_base) if vault_base is not None else DEFAULT_VAULT_BASE
    paths: list[tuple[str, Path]] = []
    for entry in sorted(base.iterdir()):
        if not entry.is_dir() or not entry.name.startswith("full_dataset_"):
            continue
        manifest = entry / "manifest.csv"
        if not manifest.is_file():
            continue
        match = re.match(r"full_dataset_(it\d+)", entry.name)
        dataset_id = match.group(1) if match else entry.name.replace("full_dataset_", "").split("_")[0]
        paths.append((dataset_id, manifest))
    return paths


def load_manifest_rows(vault_base: Path | str | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for dataset_id, manifest in discover_manifest_paths(vault_base):
        with manifest.open(newline="") as f:
            for row in csv.DictReader(f):
                enriched = dict(row)
                raw_sample_id = str(row.get("sample_id", ""))
                enriched["_dataset_id"] = dataset_id
                enriched["_manifest_path"] = str(manifest)
                enriched["_raw_sample_id"] = raw_sample_id
                enriched["sample_id"] = f"{dataset_id}_{raw_sample_id}"
                enriched["_ro_count_int"] = _to_int(row.get("ro_count"))
                enriched["_lut_count_float"] = _to_float(row.get("lut_count"))
                rows.append(enriched)
    return rows


def compute_endpoint_heuristic(manifest_rows: Sequence[dict[str, Any]]) -> RoLutHeuristic:
    standalone = [
        row
        for row in manifest_rows
        if str(row.get("class_label", "")) == "1"
        and row.get("_ro_count_int") is not None
        and row.get("_lut_count_float") is not None
    ]
    if not standalone:
        raise ValueError("no standalone manifest rows with numeric ro_count and lut_count")
    min_ro = min(int(row["_ro_count_int"]) for row in standalone)
    max_ro = max(int(row["_ro_count_int"]) for row in standalone)
    if max_ro <= min_ro:
        raise ValueError(f"cannot estimate LUTs/RO from endpoint RO counts {min_ro} and {max_ro}")
    min_luts = [float(row["_lut_count_float"]) for row in standalone if int(row["_ro_count_int"]) == min_ro]
    max_luts = [float(row["_lut_count_float"]) for row in standalone if int(row["_ro_count_int"]) == max_ro]
    min_lut_mean = mean(min_luts)
    max_lut_mean = mean(max_luts)
    luts_per_ro = (max_lut_mean - min_lut_mean) / float(max_ro - min_ro)
    fixed_overhead_luts = min_lut_mean - luts_per_ro * min_ro
    return RoLutHeuristic(
        min_ro=min_ro,
        max_ro=max_ro,
        min_lut_mean=min_lut_mean,
        max_lut_mean=max_lut_mean,
        luts_per_ro=luts_per_ro,
        fixed_overhead_luts=fixed_overhead_luts,
        min_count=len(min_luts),
        max_count=len(max_luts),
    )


def manifest_index_by_sample_id(manifest_rows: Sequence[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {str(row.get("sample_id", "")): row for row in manifest_rows if row.get("sample_id")}


def standalone_manifest_points(
    manifest_rows: Sequence[dict[str, Any]],
    heuristic: RoLutHeuristic,
) -> list[dict[str, Any]]:
    points = []
    for row in manifest_rows:
        if str(row.get("class_label", "")) != "1":
            continue
        ro_count = row.get("_ro_count_int")
        lut_count = row.get("_lut_count_float")
        if ro_count is None or lut_count is None:
            continue
        predicted_ro_luts = float(ro_count) * heuristic.luts_per_ro
        actual_ro_luts = float(lut_count) - heuristic.fixed_overhead_luts
        points.append(
            {
                "sample_id": row.get("sample_id", ""),
                "dataset_id": row.get("_dataset_id", ""),
                "ro_count": int(ro_count),
                "lut_count": float(lut_count),
                "predicted_ro_luts": predicted_ro_luts,
                "actual_ro_luts": actual_ro_luts,
                "residual_luts": actual_ro_luts - predicted_ro_luts,
            }
        )
    return points

