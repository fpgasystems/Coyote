"""Path helpers for the hls4ml workspace under ml_baseline."""

from __future__ import annotations

import sys
from pathlib import Path


EXAMPLE_ROOT = Path(__file__).resolve().parents[1]
ML_BASELINE_ROOT = EXAMPLE_ROOT.parent
EXAMPLES_ROOT = ML_BASELINE_ROOT.parent
COYOTE_ROOT = EXAMPLES_ROOT.parent
ARTIFACTS_ROOT = EXAMPLE_ROOT / "artifacts"
CONFIGS_ROOT = EXAMPLE_ROOT / "configs"


def ensure_ml_baseline_on_path() -> None:
    """Allow direct imports from the parent ml_baseline workspace."""
    ml_baseline = str(ML_BASELINE_ROOT)
    if ml_baseline not in sys.path:
        sys.path.insert(0, ml_baseline)
