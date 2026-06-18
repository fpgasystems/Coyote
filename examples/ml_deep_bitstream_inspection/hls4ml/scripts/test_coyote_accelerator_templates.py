#!/usr/bin/env python3
"""Smoke-check raw CoyoteAccelerator pipeline templates against the known-good artifact."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "pipeline/coyote_accelerator/templates"


def render_template(name: str, **values: object) -> str:
    text = (TEMPLATE_DIR / name).read_text()
    for key, value in values.items():
        text = text.replace("{{" + key + "}}", str(value))
    return text


DEFAULT_GOLDEN = Path(
    "/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml/"
    "reproducibility/zero_in_coyote_accel_downsampler_hls4ml_e2e_20260517/"
    "sources/generated_project/src"
)


def strip_comments_and_blank_lines(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        lines.append(stripped)
    return "\n".join(lines) + "\n"


def assert_equal(label: str, expected: str, actual: str, *, ignore_comments: bool = False) -> None:
    if ignore_comments:
        expected = strip_comments_and_blank_lines(expected)
        actual = strip_comments_and_blank_lines(actual)
    if expected != actual:
        raise AssertionError(f"{label} does not match the known-good generated artifact")
    print(f"[ok] {label}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--golden-src", type=Path, default=DEFAULT_GOLDEN)
    args = parser.parse_args()

    golden = args.golden_src.resolve()
    assert_equal(
        "zero_in_raw_downsample.hpp",
        (golden / "hls/model_wrapper/firmware/zero_in_raw_downsample.hpp").read_text(),
        render_template("zero_in_raw_downsample.hpp.in", ZERO_IN_PIXELS="256 * 256"),
    )
    assert_equal(
        "zero_in_coyote_accel_test.cpp",
        (golden / "zero_in_coyote_accel_test.cpp").read_text(),
        render_template("raw_test.cpp.in", PROJECT_NAME="zero_in_coyote_accel"),
    )
    assert_equal(
        "host_libs.cpp",
        (golden / "host_libs.cpp").read_text(),
        (TEMPLATE_DIR / "host_libs.cpp").read_text(),
        ignore_comments=True,
    )
    assert_equal(
        "host_libs.hpp",
        (golden / "host_libs.hpp").read_text(),
        (TEMPLATE_DIR / "host_libs.hpp").read_text(),
        ignore_comments=True,
    )


if __name__ == "__main__":
    main()
