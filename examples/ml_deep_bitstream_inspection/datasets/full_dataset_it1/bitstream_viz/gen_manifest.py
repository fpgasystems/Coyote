#!/usr/bin/env python3
"""Generate a preliminary manifest CSV from the available full-dataset builds.

Scans BENIGN_FP00 and STAND_FP00 build directories for bitstreams and
synthesizes a manifest compatible with the pilot bitstream_viz pipeline.
"""

import csv
import hashlib
import os
import re
import sys

BUILDS_DIR = "/mnt/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/datasets/full_dataset_it1/builds"
OUTPUT_CSV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prelim_manifest.csv")

# Config-to-app mapping from CMakeLists.txt
BENIGN_APPS = {
    0:  ("A01", "hello_world",              "base"),
    1:  ("A02", "hls_vadd",                 "base"),
    2:  ("A03", "multitenancy_aes",         "base"),
    3:  ("A04", "user_interrupts",          "base"),
    4:  ("A05", "perf_fpga",                "base"),
    5:  ("A06", "multithreading_aes",       "base"),
    6:  ("A07", "euclidean",                "base"),
    7:  ("A08", "cosine",                   "base"),
    8:  ("V01", "hello_world_nodbg",        "nodbg"),
    9:  ("V02", "hls_vadd_nodbg",           "nodbg"),
    10: ("V03", "multitenancy_aes_nodbg",   "nodbg"),
    11: ("V04", "user_interrupts_nodbg",    "nodbg"),
    12: ("V05", "perf_fpga_nodbg",          "nodbg"),
    13: ("V06", "multithreading_aes_nodbg", "nodbg"),
    14: ("V07", "euclidean_nodbg",          "nodbg"),
}

STAND_RO_COUNTS = {
    0:  4,
    1:  16,
    2:  64,
    3:  256,
    4:  1024,
    5:  4096,
    6:  8192,
    7:  10000,
    8:  12000,
    9:  14000,
    10: 16000,
    11: 18000,
    12: 19000,
    13: 20000,
    14: 22000,
}

# LUT counts from synthesis reports (pre-extracted)
BENIGN_LUTS = {
    0: 13718, 1: 20307, 2: 35538, 3: 11037, 4: 13734,
    5: 26783, 6: 20799, 7: 20833, 8: 9580, 9: 13868,
    10: 31149, 11: 8372, 12: 9850, 13: 20408, 14: 14360,
}

STAND_LUTS = {
    0: 8384, 1: 8420, 2: 8564, 3: 9140, 4: 11444,
    5: 20660, 6: 32948, 7: 38372, 8: 44336, 9: 50336,
    10: 56336, 11: 62336, 12: 65336, 13: 68336, 14: 74336,
}

FIELDS = [
    "sample_id", "class_label", "class_name", "base_app_id", "app_id",
    "variant_id", "source_type", "region_id", "config_id", "batch_id",
    "floorplan_id", "ro_count", "lut_count", "bitstream_path", "file_size",
]


def scan_batch(batch_id, class_label, class_name):
    """Scan a batch directory and return manifest rows for available bitstreams."""
    rows = []
    batch_dir = os.path.join(BUILDS_DIR, batch_id, "build_hw", "bitstreams")
    if not os.path.isdir(batch_dir):
        return rows

    for config_idx in range(15):
        bin_path = os.path.join(batch_dir, f"config_{config_idx}",
                                f"vfpga_c{config_idx}_0.bin")
        if not os.path.isfile(bin_path):
            continue

        file_size = os.path.getsize(bin_path)

        if class_label == 0:  # benign
            app_id, app_name, source_type = BENIGN_APPS[config_idx]
            ro_count = 0
            lut_count = BENIGN_LUTS.get(config_idx, 0)
            sample_id = f"B{len(rows):03d}"
        else:  # standalone
            ro = STAND_RO_COUNTS[config_idx]
            app_id = f"RO_{ro:05d}"
            app_name = f"ro_{ro:04d}" if ro < 10000 else f"ro_{ro}"
            source_type = "standalone"
            ro_count = ro
            lut_count = STAND_LUTS.get(config_idx, 0)
            sample_id = f"S{len(rows):03d}"

        # Relative bitstream path from builds dir
        rel_path = os.path.relpath(bin_path, BUILDS_DIR)

        rows.append({
            "sample_id": sample_id,
            "class_label": class_label,
            "class_name": class_name,
            "base_app_id": app_name,
            "app_id": app_id,
            "variant_id": "benign" if class_label == 0 else "standalone",
            "source_type": source_type,
            "region_id": 0,
            "config_id": config_idx,
            "batch_id": batch_id,
            "floorplan_id": "FP00",
            "ro_count": ro_count,
            "lut_count": lut_count,
            "bitstream_path": rel_path,
            "file_size": file_size,
        })

    return rows


def main():
    all_rows = []

    # Scan available batches
    benign_rows = scan_batch("BENIGN_FP00", 0, "benign")
    stand_rows = scan_batch("STAND_FP00", 1, "standalone")

    # Re-number sample IDs globally
    for i, row in enumerate(benign_rows):
        row["sample_id"] = f"B{i:03d}"
    for i, row in enumerate(stand_rows):
        row["sample_id"] = f"S{i:03d}"

    all_rows = benign_rows + stand_rows

    # Write CSV
    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(all_rows)

    print(f"Manifest: {len(all_rows)} samples ({len(benign_rows)} benign, "
          f"{len(stand_rows)} standalone)")
    print(f"Written to: {OUTPUT_CSV}")


if __name__ == "__main__":
    main()
