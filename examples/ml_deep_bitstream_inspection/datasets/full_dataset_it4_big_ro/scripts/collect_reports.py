#!/usr/bin/env python3
"""Collect timing and utilization reports from big-hammer RO builds."""

import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import BASE, BATCH_ORDER, CONFIG_COUNT, RO_COUNTS, RO_TARGET_PCTS
from job_paths import output_context

NUMBER_RE = re.compile(r'[-+]?\d+(?:\.\d+)?')


def parse_timing_report(report_path):
    """Extract WNS from a timing summary report."""
    if not os.path.exists(report_path):
        return None, "MISSING"

    seen_header = False
    seen_separator = False
    with open(report_path, 'r', errors='ignore') as f:
        for line in f:
            if not seen_header:
                seen_header = "WNS(ns)" in line and "TNS(ns)" in line
                continue
            if not seen_separator:
                seen_separator = "-------" in line
                continue
            match = NUMBER_RE.search(line)
            if not match:
                return None, "UNKNOWN"
            wns = float(match.group(0))
            status = "PASS" if wns > 0 else ("MARGINAL" if wns == 0 else "FAIL")
            return wns, status

    return None, "UNKNOWN"


def get_timing_report_path(build_dir, built_config):
    report_dir = os.path.join(build_dir, "reports", f"config_{built_config}")
    candidates = [
        os.path.join(report_dir, f"shell_timing_summary_c{built_config}.rpt"),
        os.path.join(report_dir, f"timing_summary_c{built_config}.rpt"),
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return candidates[0]


def parse_table_value(value):
    match = NUMBER_RE.search(value.replace(",", ""))
    return match.group(0) if match else "0"


def parse_utilization_report(report_path):
    result = {"lut_count": "0", "ff_count": "0", "bram_count": "0", "dsp_count": "0"}

    if not os.path.exists(report_path):
        return result

    with open(report_path, 'r', errors='ignore') as f:
        for line in f:
            parts = [part.strip() for part in line.split('|')]
            if len(parts) < 3:
                continue
            label = parts[1].rstrip('*').strip()
            value = parse_table_value(parts[2])
            if label == "CLB LUTs":
                result["lut_count"] = value
            elif label in ("CLB Registers", "Slice Registers"):
                result["ff_count"] = value
            elif label == "Block RAM Tile":
                result["bram_count"] = value
            elif label == "DSPs":
                result["dsp_count"] = value

    return result


def collect_batch(batch_id):
    build_dir = os.path.join(BASE, "builds", batch_id, "build_hw")
    reports = []

    for config_local in range(CONFIG_COUNT):
        report = {
            "config_local": config_local,
            "batch_id": batch_id,
            "ro_count": RO_COUNTS[config_local],
            "target_ro_lut_pct": RO_TARGET_PCTS[config_local],
        }

        build_dir, built_config = output_context(batch_id, config_local)

        timing_path = get_timing_report_path(build_dir, built_config)
        wns, status = parse_timing_report(timing_path)
        report["wns"] = wns
        report["timing_status"] = status

        util_path = os.path.join(
            build_dir, "reports", f"config_{built_config}",
            f"user_synthed_c{built_config}_0.rpt",
        )
        report.update(parse_utilization_report(util_path))

        bin_path = os.path.join(
            build_dir, "bitstreams", f"config_{built_config}",
            f"vfpga_c{built_config}_0.bin",
        )
        report["bin_exists"] = os.path.exists(bin_path)
        report["bin_path"] = bin_path
        reports.append(report)

    return reports


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", help="Batch ID")
    parser.add_argument("--all", action="store_true", help="Collect all batches")
    parser.add_argument("--output", default=None, help="Output CSV path")
    args = parser.parse_args()

    all_reports = []

    if args.all:
        for batch_id in BATCH_ORDER:
            reports = collect_batch(batch_id)
            all_reports.extend(reports)
            print(f"  {batch_id}: {len(reports)} configs collected")
    elif args.batch:
        all_reports = collect_batch(args.batch)
        print(f"  {args.batch}: {len(all_reports)} configs collected")
    else:
        parser.print_help()
        return

    if not all_reports:
        print("No reports found.")
        return

    output_path = args.output or os.path.join(BASE, "artifacts", "reports_raw.csv")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    fieldnames = [
        "batch_id", "config_local", "ro_count", "target_ro_lut_pct",
        "timing_status", "wns", "lut_count", "ff_count", "bram_count",
        "dsp_count", "bin_exists", "bin_path",
    ]
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_reports)

    print(f"\nWrote {len(all_reports)} rows to {output_path}")


if __name__ == "__main__":
    main()
