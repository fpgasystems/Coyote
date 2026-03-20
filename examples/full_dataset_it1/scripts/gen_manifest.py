#!/usr/bin/env python3
"""Generate the full dataset manifest by merging batch reports.

Combines per-batch results into a single manifest.csv with global config IDs
and sample IDs.

Usage:
    python3 gen_manifest.py
"""

import csv
import hashlib
import os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Batch ordering (determines global config ID assignment)
BATCH_ORDER = [
    "BENIGN_FP00", "BENIGN_FP01", "BENIGN_FP02", "BENIGN_FP03", "BENIGN_FP04",
    "STAND_FP00",  "STAND_FP01",  "STAND_FP02",  "STAND_FP03",  "STAND_FP04",
]

# App catalogs (matching gen_cmakelists.py ordering)
BENIGN_APPS = [
    ("A01", "hello_world",        "base"),
    ("A02", "hls_vadd",           "base"),
    ("A03", "multitenancy_aes",   "base"),
    ("A04", "user_interrupts",    "base"),
    ("A05", "perf_fpga",          "base"),
    ("A06", "multithreading_aes", "base"),
    ("A07", "euclidean",          "base"),
    ("A08", "cosine",             "base"),
    ("V01", "hello_world_nodbg",        "nodbg"),
    ("V02", "hls_vadd_nodbg",           "nodbg"),
    ("V03", "multitenancy_aes_nodbg",   "nodbg"),
    ("V04", "user_interrupts_nodbg",    "nodbg"),
    ("V05", "perf_fpga_nodbg",          "nodbg"),
    ("V06", "multithreading_aes_nodbg", "nodbg"),
    ("V07", "euclidean_nodbg",          "nodbg"),
]

RO_COUNTS = [4, 8, 12, 24, 48, 96, 192, 384, 768, 1024, 1536, 2048, 3072, 4096, 5000]
STANDALONE_APPS = [
    (f"RO_{nro:04d}", f"ro_{nro:04d}", "standalone")
    for nro in RO_COUNTS
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


def main():
    shell_id = get_shell_id()
    tool_version = "Vivado v.2024.2"

    rows = []
    global_config = 0

    for batch_id in BATCH_ORDER:
        is_benign = batch_id.startswith("BENIGN_")
        fp_id = batch_id.split("_", 1)[1]  # FP00, FP01, etc.
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
            timing_status = "PENDING"
            lut_count = ff_count = bram_count = dsp_count = 0

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
                "validation_status": "PENDING",
                "file_hash": file_hash,
                "notes": "",
            }
            rows.append(row)
            global_config += 1

    # Write manifest
    output_path = os.path.join(BASE, "artifacts", "manifest.csv")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    fieldnames = list(rows[0].keys())
    with open(output_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Manifest: {len(rows)} rows written to {output_path}")
    print(f"  Benign: {sum(1 for r in rows if r['class_label'] == 0)}")
    print(f"  Standalone: {sum(1 for r in rows if r['class_label'] == 1)}")
    print(f"  Shell ID: {shell_id}")


if __name__ == "__main__":
    main()
