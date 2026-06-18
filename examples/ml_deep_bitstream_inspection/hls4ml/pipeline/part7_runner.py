"""Part 7 of the notebook flow: toolchain setup and stage dispatch."""

from __future__ import annotations

import os
import re
import shlex
import shutil
import sys
from pathlib import Path
from typing import Iterable, Sequence

from .part1_common import FlowContext, write_run_index, write_top_manifests
from .part2_train import stage_train
from .part3_hls import stage_hls
from .part4_bitstream import stage_bitstream
from .part5_deploy import stage_deploy
from .part6_validate import stage_validate

def discover_toolchain_version(requested: str = "latest") -> str | None:
    roots = [Path("/tools/Xilinx/Vivado"), Path("/tools/Xilinx/Vitis"), Path("/tools/Xilinx/Vitis_HLS")]
    versions_by_root = []
    for root in roots:
        if not root.exists():
            continue
        versions = {path.name for path in root.iterdir() if path.is_dir()}
        versions_by_root.append(versions)
    if not versions_by_root:
        return None
    common = set.intersection(*versions_by_root) if len(versions_by_root) > 1 else versions_by_root[0]
    if requested != "latest":
        return requested if requested in common or not common else None
    if not common:
        return None

    def sort_key(value: str):
        return [int(part) if part.isdigit() else part for part in re.split(r"([0-9]+)", value)]

    return sorted(common, key=sort_key)[-1]


def maybe_reexec_with_toolchain(ctx: FlowContext, stages: set[str], argv: Sequence[str]) -> None:
    needs_toolchain = bool(stages & {"hls", "bitstream"})
    toolchain = ctx.config.get("toolchain", {})
    if not needs_toolchain or not bool(toolchain.get("auto_enable", True)):
        return
    if os.environ.get("HLS4ML_RUN_TOOLCHAIN_ENABLED") == "1":
        return
    if shutil.which("vitis_hls") and shutil.which("vivado"):
        return
    version = discover_toolchain_version(str(toolchain.get("version", "latest")))
    if version is None:
        return
    python = shlex.quote(sys.executable)
    quoted_argv = " ".join(shlex.quote(arg) for arg in argv)
    prologue = "\n".join(
        [
            "export CLI_PATH=/opt/hdev/cli",
            "export TERM=${TERM:-xterm}",
            "export HLS4ML_RUN_TOOLCHAIN_ENABLED=1",
            f'source /opt/hdev/cli/enable/vivado -v "{version}"',
            f'source /opt/hdev/cli/enable/vitis -v "{version}"',
            f"exec {python} {quoted_argv}",
        ]
    )
    print(f"[toolchain] re-execing with Vivado/Vitis {version}")
    os.execv("/bin/bash", ["bash", "-lc", prologue])


STAGE_FUNCS = {
    "train": stage_train,
    "hls": stage_hls,
    "bitstream": stage_bitstream,
    "deploy": stage_deploy,
    "validate": stage_validate,
}


def run_stages(ctx: FlowContext, stages: Iterable[str], force: bool = False, force_fingerprint: bool = False) -> None:
    write_top_manifests(ctx, force_fingerprint=force_fingerprint or force)
    for stage in stages:
        if stage not in STAGE_FUNCS:
            raise ValueError(f"Unknown stage {stage!r}; choose from {sorted(STAGE_FUNCS)}")
        print(f"[stage] {stage}")
        if stage == "hls":
            stage_hls(ctx, force=force, force_fingerprint=force_fingerprint or force)
        else:
            STAGE_FUNCS[stage](ctx, force=force)
    write_run_index(ctx)
