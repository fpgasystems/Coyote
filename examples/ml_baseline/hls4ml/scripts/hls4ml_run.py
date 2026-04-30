#!/usr/bin/env python3
"""Run the pruned-QAT hls4ml notebook flow from a YAML config."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
os.environ.setdefault("TF_USE_LEGACY_KERAS", "1")

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))


def reexec_local_python_if_needed() -> None:
    if os.environ.get("HLS4ML_RUN_NO_VENV") == "1":
        return
    candidates = [
        EXAMPLE_ROOT.parent / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT.parent / ".venv" / "bin" / "python",
        EXAMPLE_ROOT / ".venv_hls4ml" / "bin" / "python",
        EXAMPLE_ROOT / ".venv" / "bin" / "python",
    ]
    current = Path(sys.executable).resolve()
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK) and candidate.resolve() != current:
            os.execv(str(candidate), [str(candidate), *sys.argv])


AVAILABLE_STAGES = ("train", "hls", "bitstream", "deploy", "validate")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="YAML/JSON run config")
    parser.add_argument("--run-root", type=Path, default=None, help="Existing or explicit run root")
    parser.add_argument("--hls-sweep-root", type=Path, default=None, help="Existing or explicit hls4ml sweep root")
    parser.add_argument(
        "--stages",
        default="train,hls",
        help=f"Comma-separated stages. Available: {','.join(AVAILABLE_STAGES)}",
    )
    parser.add_argument("--force", action="store_true", help="Ignore cache manifests for requested stages")
    parser.add_argument(
        "--force-fingerprint",
        action="store_true",
        help=(
            "Overwrite stored fingerprint in existing run manifests instead of raising on mismatch. "
            "Use for deliberate backfills when source code changed but training config did not."
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    reexec_local_python_if_needed()
    from pipeline.notebook_flow import build_context, load_config, maybe_reexec_with_toolchain, run_stages

    config_path = args.config.resolve()
    config = load_config(config_path)
    ctx = build_context(config, config_path=config_path, run_root_arg=args.run_root, hls_sweep_root_arg=args.hls_sweep_root)
    stages = [stage.strip() for stage in args.stages.split(",") if stage.strip()]
    maybe_reexec_with_toolchain(ctx, set(stages), sys.argv)
    run_stages(ctx, stages, force=args.force, force_fingerprint=args.force_fingerprint)
    print(f"[done] run_root={ctx.run_root}")
    print(f"[done] run_index={ctx.run_root / 'run_index.md'}")


if __name__ == "__main__":
    main()
