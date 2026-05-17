#!/usr/bin/env python3
"""Generate the big-hammer RO dataset manifest."""

import csv
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import (BASE, BATCH_ORDER, CONFIG_COUNT, LUTS_PER_RO,
                            RO_COUNTS, RO_TARGET_PCTS,
                            STANDALONE_APPS_MANIFEST, TARGET_DEVICE,
                            TARGET_DEVICE_LUTS)
from job_paths import bitstream_path_for

MANIFEST_FIELDS = [
    "sample_id", "class_label", "class_name", "source_type", "app_id",
    "app_name", "variant_id", "floorplan_id", "ro_count",
    "target_ro_lut_count", "target_ro_lut_pct", "target_device",
    "target_device_luts", "batch_id", "config_local", "config_global",
    "shell_id", "tool_version", "bitstream_path", "timing_status",
    "wns", "lut_count", "ff_count", "bram_count", "dsp_count",
    "validation_status", "file_hash", "notes",
]


def sha256_file(path):
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                h.update(chunk)
        return h.hexdigest()
    except FileNotFoundError:
        return "MISSING"


def get_shell_id():
    candidates = []
    for batch_id in BATCH_ORDER:
        build_dir = os.path.join(BASE, "builds", batch_id, "build_hw")
        candidates.extend([
            os.path.join(build_dir, "checkpoints", "shell_routed_locked.dcp"),
            os.path.join(build_dir, "checkpoints", "config_0", "shell_routed_c0.dcp"),
            os.path.join(build_dir, "checkpoints", "shell_routed.dcp"),
        ])
    jobs_dir = os.path.join(BASE, "jobs")
    if os.path.exists(jobs_dir):
        for root, _, files in os.walk(jobs_dir):
            for filename in files:
                if filename == "shell_routed_c0.dcp":
                    candidates.append(os.path.join(root, filename))
    for path in candidates:
        if os.path.exists(path):
            return sha256_file(path)[:8]
    return "TBD"


def load_reports():
    reports_path = os.path.join(BASE, "artifacts", "reports_raw.csv")
    reports = {}
    if not os.path.exists(reports_path):
        return reports

    with open(reports_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                config_local = int(row["config_local"])
            except (KeyError, TypeError, ValueError):
                continue
            reports[(row.get("batch_id", ""), config_local)] = row

    return reports


def validation_status(file_hash, report):
    if file_hash == "MISSING":
        return "MISSING"
    if not report:
        return "PENDING"
    return report.get("timing_status") or "UNKNOWN"


def write_manifest(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def main():
    shell_id = get_shell_id()
    tool_version = "Vivado v.2024.2"
    reports = load_reports()

    rows = []
    global_config = 0

    for batch_id in BATCH_ORDER:
        fp_id = batch_id.split("_", 1)[1]

        for config_local in range(CONFIG_COUNT):
            app_id, app_name, source_type = STANDALONE_APPS_MANIFEST[config_local]
            ro_count = RO_COUNTS[config_local]
            target_ro_lut_count = ro_count * LUTS_PER_RO
            target_ro_lut_pct = target_ro_lut_count / TARGET_DEVICE_LUTS * 100.0

            bin_local = bitstream_path_for(batch_id, config_local)
            bin_global = f"config_{global_config:03d}/vfpga_c{global_config:03d}_0.bin"
            file_hash = sha256_file(bin_local)
            report = reports.get((batch_id, config_local), {})

            rows.append({
                "sample_id": f"S{global_config:03d}",
                "class_label": 1,
                "class_name": "standalone",
                "source_type": source_type,
                "app_id": app_id,
                "app_name": app_name,
                "variant_id": "big_hammer_ro",
                "floorplan_id": fp_id,
                "ro_count": ro_count,
                "target_ro_lut_count": target_ro_lut_count,
                "target_ro_lut_pct": f"{target_ro_lut_pct:.4f}",
                "target_device": TARGET_DEVICE,
                "target_device_luts": TARGET_DEVICE_LUTS,
                "batch_id": batch_id,
                "config_local": config_local,
                "config_global": global_config,
                "shell_id": shell_id,
                "tool_version": tool_version,
                "bitstream_path": bin_global,
                "timing_status": report.get("timing_status", "PENDING"),
                "wns": report.get("wns", ""),
                "lut_count": report.get("lut_count", "0"),
                "ff_count": report.get("ff_count", "0"),
                "bram_count": report.get("bram_count", "0"),
                "dsp_count": report.get("dsp_count", "0"),
                "validation_status": validation_status(file_hash, report),
                "file_hash": file_hash,
                "notes": f"target_pct_nominal={RO_TARGET_PCTS[config_local]:.1f}",
            })
            global_config += 1

    output_path = os.path.join(BASE, "artifacts", "manifest.csv")
    available_path = os.path.join(BASE, "artifacts", "manifest_available.csv")
    available_rows = [row for row in rows if row["file_hash"] != "MISSING"]

    write_manifest(output_path, rows)
    write_manifest(available_path, available_rows)

    print(f"Manifest: {len(rows)} rows written to {output_path}")
    print(f"Available manifest: {len(available_rows)} rows written to {available_path}")
    print(f"  Standalone: {len(rows)}")
    print(f"  Shell ID: {shell_id}")
    print(f"  Reports merged: {len(reports)}")


if __name__ == "__main__":
    main()
