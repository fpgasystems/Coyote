#!/usr/bin/env python3
"""Package batch outputs into the final artifacts directory.

Copies bitstreams, reports, checkpoints, and sources from per-batch build
directories into a unified artifacts/ directory with global config IDs.

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
    os.makedirs(os.path.join(artifacts, "reports"), exist_ok=True)
    os.makedirs(os.path.join(artifacts, "checkpoints"), exist_ok=True)
    os.makedirs(os.path.join(artifacts, "sources"), exist_ok=True)
    os.makedirs(os.path.join(artifacts, "logs"), exist_ok=True)

    global_config = 0
    copied_bins = 0
    copied_reports = 0

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

            # Reports
            src_rpt_dir = os.path.join(build_dir, "reports", f"config_{config_local}")
            dst_rpt_dir = os.path.join(artifacts, "reports", global_dir)
            if os.path.exists(src_rpt_dir):
                if os.path.exists(dst_rpt_dir):
                    shutil.rmtree(dst_rpt_dir)
                shutil.copytree(src_rpt_dir, dst_rpt_dir)
                copied_reports += 1

            # Per-config checkpoint
            src_dcp = os.path.join(build_dir, "checkpoints", f"config_{config_local}",
                                   f"shell_routed_c{config_local}.dcp")
            if os.path.exists(src_dcp):
                dst_dcp_dir = os.path.join(artifacts, "checkpoints", global_dir)
                os.makedirs(dst_dcp_dir, exist_ok=True)
                shutil.copy2(src_dcp, os.path.join(dst_dcp_dir,
                             f"shell_routed_c{global_config:03d}.dcp"))

            global_config += 1

        # Copy batch log
        for log_suffix in ["cmake", "project", "synth", "link", "shell", "app", "bitgen"]:
            src_log = os.path.join(BASE, "logs", f"{batch_id}_{log_suffix}.log")
            if os.path.exists(src_log):
                shutil.copy2(src_log, os.path.join(artifacts, "logs",
                             f"{batch_id}_{log_suffix}.log"))

        print(f"  {batch_id}: packaged")

    # Copy shell checkpoints from first batch that has them
    for batch_id in BATCH_ORDER:
        shell_dcp = os.path.join(BASE, "builds", batch_id, "build_hw",
                                 "checkpoints", "shell_routed.dcp")
        if os.path.exists(shell_dcp):
            shutil.copy2(shell_dcp,
                         os.path.join(artifacts, "checkpoints", "shell_routed.dcp"))
            locked = shell_dcp.replace("shell_routed.dcp", "shell_routed_locked.dcp")
            if os.path.exists(locked):
                shutil.copy2(locked,
                             os.path.join(artifacts, "checkpoints", "shell_routed_locked.dcp"))
            break

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
    print(f"  Report sets copied: {copied_reports}/150")
    print(f"  Output: {artifacts}/")


if __name__ == "__main__":
    main()
