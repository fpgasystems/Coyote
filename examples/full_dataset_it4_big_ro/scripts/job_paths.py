#!/usr/bin/env python3
"""Helpers for split single-bitstream job builds."""

import os

from dataset_config import BASE, BATCH_ORDER, CONFIG_COUNT, RO_COUNTS


DEFAULT_JOB_ROOT = "jobs"
RECOVERY_JOB_ROOT = "jobs_banked4096"


def global_config_for(batch_id, config_local):
    return BATCH_ORDER.index(batch_id) * CONFIG_COUNT + config_local


def part_for_global_config(global_config):
    midpoint = len(BATCH_ORDER) * CONFIG_COUNT // 2
    return "part1" if global_config < midpoint else "part2"


def job_id_for(batch_id, config_local):
    global_config = global_config_for(batch_id, config_local)
    ro_count = RO_COUNTS[config_local]
    return f"S{global_config:03d}_{batch_id}_c{config_local:02d}_ro_{ro_count}"


def active_job_root():
    return os.environ.get("JOB_ROOT", DEFAULT_JOB_ROOT)


def job_root_candidates():
    env_roots = os.environ.get("JOB_ROOT_CANDIDATES")
    if env_roots:
        candidates = [root for root in env_roots.split(":") if root]
    else:
        candidates = [active_job_root(), RECOVERY_JOB_ROOT, DEFAULT_JOB_ROOT]

    result = []
    for root in candidates:
        if root not in result:
            result.append(root)
    return result


def job_build_dir(batch_id, config_local, job_root=None):
    global_config = global_config_for(batch_id, config_local)
    part = part_for_global_config(global_config)
    job_id = job_id_for(batch_id, config_local)
    return os.path.join(BASE, job_root or active_job_root(), part, job_id, "build_hw")


def job_bin_path(batch_id, config_local, job_root=None):
    build_dir = job_build_dir(batch_id, config_local, job_root)
    return os.path.join(build_dir, "bitstreams", "config_0", "vfpga_c0_0.bin")


def grouped_build_dir(batch_id):
    return os.path.join(BASE, "builds", batch_id, "build_hw")


def output_context(batch_id, config_local):
    """Return (build_dir, built_config_index), preferring recovery job outputs."""
    for root in job_root_candidates():
        build_dir = job_build_dir(batch_id, config_local, root)
        if os.path.exists(job_bin_path(batch_id, config_local, root)):
            return build_dir, 0

    for root in job_root_candidates():
        build_dir = job_build_dir(batch_id, config_local, root)
        if os.path.isdir(build_dir):
            return build_dir, 0

    grouped = grouped_build_dir(batch_id)
    grouped_bin = os.path.join(
        grouped, "bitstreams", f"config_{config_local}",
        f"vfpga_c{config_local}_0.bin",
    )
    if os.path.exists(grouped_bin) or os.path.isdir(grouped):
        return grouped, config_local

    return job_build_dir(batch_id, config_local), 0


def bitstream_path_for(batch_id, config_local):
    build_dir, built_config = output_context(batch_id, config_local)
    return os.path.join(
        build_dir, "bitstreams", f"config_{built_config}",
        f"vfpga_c{built_config}_0.bin",
    )
