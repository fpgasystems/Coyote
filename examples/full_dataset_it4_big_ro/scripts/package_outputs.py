#!/usr/bin/env python3
"""Package big-hammer RO batch outputs into artifacts/."""

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import BASE, BATCH_ORDER, CONFIG_COUNT
from job_paths import bitstream_path_for


def main():
    artifacts = os.path.join(BASE, "artifacts")
    os.makedirs(os.path.join(artifacts, "bitstreams"), exist_ok=True)
    os.makedirs(os.path.join(artifacts, "sources"), exist_ok=True)

    global_config = 0
    copied_bins = 0

    for batch_id in BATCH_ORDER:
        for config_local in range(CONFIG_COUNT):
            global_dir = f"config_{global_config:03d}"
            src_bin = bitstream_path_for(batch_id, config_local)
            dst_bin_dir = os.path.join(artifacts, "bitstreams", global_dir)
            os.makedirs(dst_bin_dir, exist_ok=True)
            if os.path.exists(src_bin):
                dst_bin = os.path.join(dst_bin_dir, f"vfpga_c{global_config:03d}_0.bin")
                shutil.copy2(src_bin, dst_bin)
                copied_bins += 1
            global_config += 1

        print(f"  {batch_id}: packaged")

    src_apps = os.path.join(BASE, "hw", "apps")
    src_fps = os.path.join(BASE, "hw", "floorplans")
    dst_apps = os.path.join(artifacts, "sources", "apps")
    dst_fps = os.path.join(artifacts, "sources", "floorplans")

    if os.path.exists(src_apps) and not os.path.exists(dst_apps):
        shutil.copytree(src_apps, dst_apps, symlinks=True)
    if os.path.exists(src_fps) and not os.path.exists(dst_fps):
        shutil.copytree(src_fps, dst_fps)

    expected = len(BATCH_ORDER) * CONFIG_COUNT
    print("\nPackaging complete:")
    print(f"  Bitstreams copied: {copied_bins}/{expected}")
    print(f"  Output: {artifacts}/")


if __name__ == "__main__":
    main()
