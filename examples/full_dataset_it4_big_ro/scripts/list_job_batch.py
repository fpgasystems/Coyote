#!/usr/bin/env python3
"""List split single-bitstream jobs as shell-safe TSV."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dataset_config import BATCH_ORDER, CONFIG_COUNT, FLOORPLANS, RO_COUNTS, RO_TARGET_PCTS
from job_paths import global_config_for, job_id_for


PART_BATCHES = {
    "part1": BATCH_ORDER[:3],
    "part2": BATCH_ORDER[3:],
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("part", choices=sorted(PART_BATCHES))
    args = parser.parse_args()

    for batch_id in PART_BATCHES[args.part]:
        fp_id = batch_id.split("_", 1)[1]
        fplan_file = FLOORPLANS[fp_id]
        for config_local in range(CONFIG_COUNT):
            global_config = global_config_for(batch_id, config_local)
            job_id = job_id_for(batch_id, config_local)
            ro_count = RO_COUNTS[config_local]
            target_pct = RO_TARGET_PCTS[config_local]
            print(
                "\t".join([
                    job_id,
                    str(global_config),
                    batch_id,
                    fp_id,
                    fplan_file,
                    str(config_local),
                    str(ro_count),
                    f"{target_pct:.1f}",
                ])
            )


if __name__ == "__main__":
    main()
