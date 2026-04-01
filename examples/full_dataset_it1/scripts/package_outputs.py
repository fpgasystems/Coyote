#!/usr/bin/env python3
"""Package batch outputs into the final artifacts directory.

Copies bitstreams and sources from per-batch build directories into a
unified artifacts/ directory with global config IDs.

Usage:
    python3 package_outputs.py
"""

import os
import shutil

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BATCH_ORDER = [
    "BENIGN_FP00", "BENIGN_FP01", "BENIGN_FP02", "BENIGN_FP03", "BENIGN_FP04",
    "STAND_FP00",  "STAND_FP01",  "STAND_FP02",  "STAND_FP03",  "STAND_FP04",
]


def main():
    artifacts = os.path.join(BASE, "artifacts")
    os.makedirs(os.path.join(artifacts, "bitstreams"), exist_ok=True)
    os.makedirs(os.path.join(artifacts, "sources"), exist_ok=True)

    global_config = 0
    copied_bins = 0

    for batch_id in BATCH_ORDER:
        build_dir = os.path.join(BASE, "builds", batch_id, "build_hw")
        if not os.path.exists(build_dir):
            print(f"  SKIP {batch_id}: build_hw not found")
            global_config += 15
            continue

        for config_local in range(15):
            global_dir = f"config_{global_config:03d}"

            # Bitstreams
            src_bin = os.path.join(build_dir, "bitstreams", f"config_{config_local}",
                                   f"vfpga_c{config_local}_0.bin")
            dst_bin_dir = os.path.join(artifacts, "bitstreams", global_dir)
            os.makedirs(dst_bin_dir, exist_ok=True)
            if os.path.exists(src_bin):
                dst_bin = os.path.join(dst_bin_dir, f"vfpga_c{global_config:03d}_0.bin")
                shutil.copy2(src_bin, dst_bin)
                copied_bins += 1

            global_config += 1

        print(f"  {batch_id}: packaged")

    # Copy sources for reproducibility
    src_apps = os.path.join(BASE, "hw", "apps")
    src_fps = os.path.join(BASE, "hw", "floorplans")
    if os.path.exists(src_apps):
        dst_apps = os.path.join(artifacts, "sources", "apps")
        if not os.path.exists(dst_apps):
            shutil.copytree(src_apps, dst_apps)
    if os.path.exists(src_fps):
        dst_fps = os.path.join(artifacts, "sources", "floorplans")
        if not os.path.exists(dst_fps):
            shutil.copytree(src_fps, dst_fps)

    print(f"\nPackaging complete:")
    print(f"  Bitstreams copied: {copied_bins}/150")
    print(f"  Output: {artifacts}/")


if __name__ == "__main__":
    main()
