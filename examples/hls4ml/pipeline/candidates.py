"""Candidate configuration loading."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

from .paths import CONFIGS_ROOT, EXAMPLE_ROOT


@dataclass(frozen=True)
class CandidateConfig:
    name: str
    model: str
    representation: str
    img_size: int
    sequence_length: int
    min_ro: int
    run_dir: Path
    saved_run_dir: Path
    folds: List[int]
    default_stage: str
    target_part: str
    fallback_part: str
    io_type: str
    strategy: str
    reuse_factors: List[int]


def _candidate_path() -> Path:
    return CONFIGS_ROOT / "candidates.yaml"


def load_candidates() -> Dict[str, CandidateConfig]:
    raw = json.loads(_candidate_path().read_text())
    candidates: Dict[str, CandidateConfig] = {}
    for name, cfg in raw["candidates"].items():
        candidates[name] = CandidateConfig(
            name=name,
            model=cfg["model"],
            representation=cfg["representation"],
            img_size=int(cfg["img_size"]),
            sequence_length=int(cfg["sequence_length"]),
            min_ro=int(cfg["min_ro"]),
            run_dir=(EXAMPLE_ROOT / cfg["run_dir"]).resolve(),
            saved_run_dir=(EXAMPLE_ROOT / cfg["saved_run_dir"]).resolve(),
            folds=list(cfg["folds"]),
            default_stage=cfg["default_stage"],
            target_part=cfg["target_part"],
            fallback_part=cfg["fallback_part"],
            io_type=cfg["io_type"],
            strategy=cfg["strategy"],
            reuse_factors=list(cfg["reuse_factors"]),
        )
    return candidates


def get_candidate(name: str | None = None) -> CandidateConfig:
    raw = json.loads(_candidate_path().read_text())
    default_name = raw["default_candidate"]
    candidates = load_candidates()
    return candidates[name or default_name]
