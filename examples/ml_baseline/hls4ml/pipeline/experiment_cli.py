"""Shared CLI helpers for hls4ml experiment scripts."""

from __future__ import annotations

import os
import sys
from pathlib import Path


def reexec_local_python_if_needed(example_root: Path) -> None:
    if os.environ.get("HLS4ML_RUN_NO_VENV") == "1":
        return
    candidates = [
        example_root.parent / ".venv_hls4ml" / "bin" / "python",
        example_root.parent / ".venv" / "bin" / "python",
        example_root / ".venv_hls4ml" / "bin" / "python",
        example_root / ".venv" / "bin" / "python",
    ]
    current = Path(sys.executable).resolve()
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK) and candidate.resolve() != current:
            os.execv(str(candidate), [str(candidate), *sys.argv])
