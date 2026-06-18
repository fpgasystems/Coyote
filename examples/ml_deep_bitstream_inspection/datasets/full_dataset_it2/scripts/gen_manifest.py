#!/usr/bin/env python3
"""Generate the dataset manifest by merging batch reports.

Combines per-batch results into a single manifest.csv with global config IDs
and sample IDs.

Usage:
    python3 gen_manifest.py
"""

import csv
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import (BASE, BATCH_ORDER, BENIGN_APPS_MANIFEST,
                            STANDALONE_APPS_MANIFEST, RO_COUNTS)

BENIGN_APPS = BENIGN_APPS_MANIFEST
STANDALONE_APPS = STANDALONE_APPS_MANIFEST
MANIFEST_FIELDS = [
    "sample_id", "class_label", "class_name", "source_type", "app_id",
    "app_name", "variant_id", "floorplan_id", "ro_count", "batch_id",
    "config_local", "config_global", "shell_id", "tool_version",
    "bitstream_path", "timing_status", "lut_count", "ff_count",
    "bram_count", "dsp_count", "validation_status", "file_hash", "notes",
]


def sha256_file(path):
    """Compute SHA-256 hash of a file."""
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(65536), b''):
                h.update(chunk)
        return h.hexdigest()
    except FileNotFoundError:
        return "MISSING"


def get_shell_id():
    """Get shell ID from any batch's shell_routed.dcp."""
    for batch_id in BATCH_ORDER:
        dcp = os.path.join(BASE, "builds", batch_id, "build_hw", "checkpoints", "shell_routed.dcp")
        if os.path.exists(dcp):
            return sha256_file(dcp)[:8]
    return "TBD"


def load_reports():
    """Load reports_raw.csv keyed by (batch_id, config_local)."""
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
    """Derive a compact manifest validation state from file and report state."""
    if file_hash == "MISSING":
        return "MISSING"
    if not report:
        return "PENDING"
    return report.get("timing_status") or "UNKNOWN"


def write_manifest(path, rows):
    """Write manifest rows with stable field ordering."""
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
        is_benign = batch_id.startswith("BENIGN_")
        fp_id = batch_id.split("_", 1)[1]  # FP05, FP06, etc.
        class_label = 0 if is_benign else 1
        class_name = "benign" if is_benign else "standalone"
        apps = BENIGN_APPS if is_benign else STANDALONE_APPS

        build_dir = os.path.join(BASE, "builds", batch_id, "build_hw")

        for config_local in range(15):
            app_id, app_name, source_type = apps[config_local]

            # Determine RO count
            ro_count = 0
            if not is_benign:
                ro_count = RO_COUNTS[config_local]

            # Sample ID
            prefix = "B" if is_benign else "S"
            benign_offset = sum(1 for b in BATCH_ORDER[:BATCH_ORDER.index(batch_id)]
                               if b.startswith(prefix[0] if prefix == "B" else "S"))
            sample_num = benign_offset * 15 + config_local
            sample_id = f"{prefix}{sample_num:03d}"

            # Bitstream path
            bin_local = os.path.join(build_dir, "bitstreams", f"config_{config_local}",
                                     f"vfpga_c{config_local}_0.bin")
            bin_global = f"config_{global_config:03d}/vfpga_c{global_config:03d}_0.bin"

            # File hash
            file_hash = sha256_file(bin_local)

            # Timing/utilization from reports
            report = reports.get((batch_id, config_local), {})
            timing_status = report.get("timing_status", "PENDING")
            lut_count = report.get("lut_count", "0")
            ff_count = report.get("ff_count", "0")
            bram_count = report.get("bram_count", "0")
            dsp_count = report.get("dsp_count", "0")

            row = {
                "sample_id": sample_id,
                "class_label": class_label,
                "class_name": class_name,
                "source_type": source_type,
                "app_id": app_id,
                "app_name": app_name,
                "variant_id": class_name,
                "floorplan_id": fp_id,
                "ro_count": ro_count,
                "batch_id": batch_id,
                "config_local": config_local,
                "config_global": global_config,
                "shell_id": shell_id,
                "tool_version": tool_version,
                "bitstream_path": bin_global,
                "timing_status": timing_status,
                "lut_count": lut_count,
                "ff_count": ff_count,
                "bram_count": bram_count,
                "dsp_count": dsp_count,
                "validation_status": validation_status(file_hash, report),
                "file_hash": file_hash,
                "notes": "",
            }
            rows.append(row)
            global_config += 1

    # Write full and available manifests.
    output_path = os.path.join(BASE, "artifacts", "manifest.csv")
    available_path = os.path.join(BASE, "artifacts", "manifest_available.csv")
    available_rows = [row for row in rows if row["file_hash"] != "MISSING"]

    write_manifest(output_path, rows)
    write_manifest(available_path, available_rows)

    print(f"Manifest: {len(rows)} rows written to {output_path}")
    print(f"Available manifest: {len(available_rows)} rows written to {available_path}")
    print(f"  Benign: {sum(1 for r in rows if r['class_label'] == 0)}")
    print(f"  Standalone: {sum(1 for r in rows if r['class_label'] == 1)}")
    print(f"  Shell ID: {shell_id}")
    print(f"  Reports merged: {len(reports)}")


if __name__ == "__main__":
    main()
