#!/usr/bin/env python3
"""Validate the full_dataset_it4_big_ro artifacts."""

import argparse
import csv
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import BATCH_ORDER, CONFIG_COUNT

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPECTED_SAMPLES = len(BATCH_ORDER) * CONFIG_COUNT


def load_manifest(path):
    with open(path, 'r') as f:
        return list(csv.DictReader(f))


def check_build_validation(rows, artifacts_dir):
    issues = []

    if len(rows) != EXPECTED_SAMPLES:
        issues.append(f"Manifest row count {len(rows)} != expected {EXPECTED_SAMPLES}")
    else:
        print(f"  [PASS] Manifest has {EXPECTED_SAMPLES} rows")

    missing_bins = []
    for row in rows:
        bin_path = os.path.join(artifacts_dir, "bitstreams", row["bitstream_path"])
        if not os.path.exists(bin_path):
            missing_bins.append(row["sample_id"])

    if missing_bins:
        issues.append(f"Missing .bin files: {len(missing_bins)}/{len(rows)}")
    else:
        print(f"  [PASS] All {len(rows)} packaged .bin files exist")

    timing_fail = [r["sample_id"] for r in rows if r.get("timing_status") == "FAIL"]
    timing_pending = [r["sample_id"] for r in rows if r.get("timing_status") == "PENDING"]
    if timing_fail:
        print(f"  [INFO] Timing FAIL recorded for {len(timing_fail)} samples")
    if timing_pending:
        print(f"  [WARN] Timing status PENDING for {len(timing_pending)} samples")
    if not timing_fail and not timing_pending:
        print("  [PASS] All timing checks passed")

    required_fields = [
        "sample_id", "class_label", "app_id", "floorplan_id",
        "batch_id", "config_global", "file_hash", "ro_count",
        "target_ro_lut_pct",
    ]
    empty = []
    for row in rows:
        for field in required_fields:
            if row.get(field) in ("", None):
                empty.append(f"{row.get('sample_id', '<missing>')}.{field}")
    if empty:
        issues.append(f"Empty required fields: {empty[:5]}...")
    else:
        print("  [PASS] Required manifest fields populated")

    return issues


def check_dataset_shape(rows):
    issues = []

    class_counts = Counter(r["class_name"] for r in rows)
    if class_counts == Counter({"standalone": EXPECTED_SAMPLES}):
        print(f"  [PASS] Standalone-only dataset: {EXPECTED_SAMPLES} samples")
    else:
        issues.append(f"Unexpected class distribution: {dict(class_counts)}")

    fp_counts = Counter(r["floorplan_id"] for r in rows)
    imbalanced = [(fp, cnt) for fp, cnt in fp_counts.items() if cnt != CONFIG_COUNT]
    if len(fp_counts) == len(BATCH_ORDER) and not imbalanced:
        print(f"  [PASS] Floorplan balance: {CONFIG_COUNT} samples per floorplan")
    else:
        issues.append(f"Floorplan imbalance: {dict(fp_counts)}")

    config_counts = Counter(int(r["config_local"]) for r in rows)
    bad_configs = [(cfg, cnt) for cfg, cnt in config_counts.items() if cnt != len(BATCH_ORDER)]
    if set(config_counts) == set(range(CONFIG_COUNT)) and not bad_configs:
        print(f"  [PASS] Config balance: each RO count appears in {len(BATCH_ORDER)} floorplans")
    else:
        issues.append(f"Config imbalance: {dict(config_counts)}")

    hashes = [r["file_hash"] for r in rows if r["file_hash"] not in ("MISSING", "")]
    if len(hashes) < len(rows):
        print(f"  [WARN] Only {len(hashes)}/{len(rows)} hashes available")
    elif len(set(hashes)) == len(hashes):
        print(f"  [PASS] All {len(hashes)} file hashes unique")
    else:
        issues.append(f"Duplicate hashes: {len(hashes) - len(set(hashes))}")

    return issues


def check_ro_targets(rows):
    issues = []
    pcts = []
    for row in rows:
        try:
            pct = float(row["target_ro_lut_pct"])
        except (KeyError, TypeError, ValueError):
            issues.append(f"Invalid target_ro_lut_pct for {row.get('sample_id')}")
            continue
        pcts.append(pct)
        if pct < 6.0 or pct > 25.0:
            issues.append(f"{row['sample_id']} target_ro_lut_pct out of range: {pct}")

    if not issues:
        print(f"  [PASS] Target RO LUT percentages are within [6, 25]")

    unique_pcts = sorted(set(round(p, 4) for p in pcts))
    if len(unique_pcts) == CONFIG_COUNT:
        print(f"  [PASS] {CONFIG_COUNT} distinct RO target percentages")
    else:
        issues.append(f"Expected {CONFIG_COUNT} target percentages, found {len(unique_pcts)}")

    return issues


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=os.path.join(BASE, "artifacts", "manifest.csv"))
    args = parser.parse_args()

    if not os.path.exists(args.manifest):
        print(f"ERROR: Manifest not found at {args.manifest}")
        print("Run gen_manifest.py first.")
        sys.exit(1)

    rows = load_manifest(args.manifest)
    artifacts_dir = os.path.dirname(args.manifest)

    print(f"=== full_dataset_it4_big_ro validation ({len(rows)} samples) ===\n")

    all_issues = []
    print("Build validation:")
    all_issues.extend(check_build_validation(rows, artifacts_dir))
    print("\nDataset shape:")
    all_issues.extend(check_dataset_shape(rows))
    print("\nRO target validation:")
    all_issues.extend(check_ro_targets(rows))

    print(f"\n{'=' * 50}")
    if all_issues:
        print(f"ISSUES FOUND: {len(all_issues)}")
        for i, issue in enumerate(all_issues, 1):
            print(f"  {i}. {issue}")
        sys.exit(1)

    print("ALL GATES PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
