#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from pipeline.notebook_flow import build_context, load_config, stage_bitstream, stage_deploy, stage_validate


STAGES = {
    "bitstream": stage_bitstream,
    "deploy": stage_deploy,
    "validate": stage_validate,
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Run selected stages against an archived hls4ml run.")
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--hls-sweep-root", required=True, type=Path)
    parser.add_argument("--stage", action="append", choices=sorted(STAGES), required=True)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    cfg_path = args.config.resolve()
    run_root = args.run_root.resolve()
    hls_sweep_root = args.hls_sweep_root.resolve()

    print(f"[info] config={cfg_path}")
    print(f"[info] run_root={run_root}")
    print(f"[info] hls_sweep_root={hls_sweep_root}")
    print(f"[info] stages={','.join(args.stage)} force={args.force}")

    ctx = build_context(
        load_config(cfg_path),
        cfg_path,
        run_root_arg=run_root,
        hls_sweep_root_arg=hls_sweep_root,
    )
    for stage in args.stage:
        print(f"[stage] {stage}")
        STAGES[stage](ctx, force=args.force)


if __name__ == "__main__":
    main()
