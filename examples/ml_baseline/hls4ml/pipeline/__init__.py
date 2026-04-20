"""Shared helpers for the examples/hls4ml workspace."""

from .candidates import CandidateConfig, get_candidate, load_candidates
from .evaluation import aggregate_candidate_metrics, evaluate_candidate_fold, export_calibration_bundle
from .hls import build_pytorch_hls_project
from .stages import compare_stage_predictions, write_stage_ledger

__all__ = [
    "CandidateConfig",
    "aggregate_candidate_metrics",
    "build_pytorch_hls_project",
    "compare_stage_predictions",
    "evaluate_candidate_fold",
    "export_calibration_bundle",
    "get_candidate",
    "load_candidates",
    "write_stage_ledger",
]
