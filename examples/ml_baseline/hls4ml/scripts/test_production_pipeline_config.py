#!/usr/bin/env python3
"""Smoke-check production-mode hls4ml pipeline config and data wiring."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
EXAMPLE_ROOT = SCRIPT_DIR.parent
if str(EXAMPLE_ROOT) not in sys.path:
    sys.path.insert(0, str(EXAMPLE_ROOT))

from pipeline.hls_layer_tuning import manual_layer_tuning
from pipeline.part1_common import build_context, load_config
from pipeline.part2_train import (
    assert_no_train_test_overlap,
    load_test_samples,
    load_training_samples,
)


DEFAULT_CONFIGS = [
    Path("hls4ml/configs/hls4ml_production/res256_layers7_W8A8_P50_manualA_production.yaml"),
    Path("hls4ml/configs/hls4ml_production/res512_layers7_W8A8_P50_manualA_production.yaml"),
]


def check_config(config_path: Path) -> None:
    cfg = load_config(config_path)
    ctx = build_context(cfg, config_path)
    if not ctx.production_mode:
        raise AssertionError(f"{config_path}: expected run.mode=production")
    if ctx.model_slot != "production":
        raise AssertionError(f"{config_path}: expected production model slot, got {ctx.model_slot}")
    if "production" not in str(ctx.hls_project_dir):
        raise AssertionError(f"{config_path}: hls_project_dir does not use production slot: {ctx.hls_project_dir}")
    tuning = manual_layer_tuning(cfg)
    expected_layers = {f"conv{i}" for i in range(7)}
    missing = expected_layers - set(tuning)
    if missing:
        raise AssertionError(f"{config_path}: missing manual tuning for {sorted(missing)}")
    if cfg.get("training", {}).get("allow_stale_fold_cache"):
        raise AssertionError(f"{config_path}: production must not allow stale fold cache")

    train_samples = load_training_samples(ctx)
    test_samples = load_test_samples(ctx)
    assert_no_train_test_overlap(load_training_samples(ctx, balance=False), test_samples)
    if not train_samples or not test_samples:
        raise AssertionError(f"{config_path}: expected non-empty train and test samples")
    print(
        f"[ok] {config_path}: train={len(train_samples)} test={len(test_samples)} "
        f"slot={ctx.model_slot} hls_project={ctx.hls_project_dir}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configs", nargs="*", type=Path, default=DEFAULT_CONFIGS)
    args = parser.parse_args()
    for config in args.configs:
        check_config(config.resolve())


if __name__ == "__main__":
    main()
