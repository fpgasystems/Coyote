"""Path helpers for the hls4ml workspace."""

from __future__ import annotations

import sys
from pathlib import Path


EXAMPLE_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = EXAMPLE_ROOT.parent
ML_BASELINE_ROOT = PROJECT_ROOT / "ml_baseline"
EXAMPLES_ROOT = PROJECT_ROOT.parent
COYOTE_ROOT = EXAMPLES_ROOT.parent
ARTIFACTS_ROOT = EXAMPLE_ROOT / "artifacts"
CONFIGS_ROOT = EXAMPLE_ROOT / "configs"


def ensure_ml_baseline_on_path() -> None:
    """Allow direct imports from the sibling ml_baseline workspace."""
    ml_baseline = str(ML_BASELINE_ROOT)
    if ml_baseline not in sys.path:
        sys.path.insert(0, ml_baseline)
