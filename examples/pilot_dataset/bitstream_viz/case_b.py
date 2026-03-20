"""Case B: deterministic byte-to-pixel grayscale images.

Each byte maps directly to one pixel. Four windowing variants:
  B1: first 65536 bytes
  B2: last 65536 bytes
  B3: centered 65536-byte window
  B4: evenly downsampled to 65536 bytes
"""

import os
import numpy as np
from PIL import Image

from config import (
    IMG_SIZE, WINDOW_SIZE, OUTPUT_DIR, DEFAULT_INVERT_B,
    VARIANT_WINDOW_MAP, CASE_B_VARIANTS,
)
from io_utils import extract_window
from metadata import build_metadata, write_metadata


def render_case_b(data, variant, invert=DEFAULT_INVERT_B):
    """Render a Case B image from raw bitstream bytes.

    Args:
        data: uint8 numpy array (full bitstream)
        variant: one of "B1", "B2", "B3", "B4"
        invert: if True, pixel = 255 - byte_value (white bg, dark data)

    Returns:
        (PIL.Image, window_mode, byte_offset_start, byte_offset_end)
    """
    window_mode = VARIANT_WINDOW_MAP[variant]
    n = len(data)

    # Compute byte offsets for metadata
    if n <= WINDOW_SIZE:
        offset_start, offset_end = 0, n
    elif window_mode == "first":
        offset_start, offset_end = 0, WINDOW_SIZE
    elif window_mode == "last":
        offset_start, offset_end = n - WINDOW_SIZE, n
    elif window_mode == "center":
        mid = n // 2
        half = WINDOW_SIZE // 2
        offset_start = mid - half
        offset_end = offset_start + WINDOW_SIZE
    else:  # downsample
        offset_start, offset_end = 0, n  # uses entire file

    window = extract_window(data, window_mode)

    if invert:
        pixels = (255 - window).astype(np.uint8)
    else:
        pixels = window

    img = Image.fromarray(pixels.reshape(IMG_SIZE, IMG_SIZE), mode="L")
    return img, window_mode, offset_start, offset_end


def generate_case_b_for_sample(sample, data, output_dir=None, invert=DEFAULT_INVERT_B):
    """Generate all 4 Case B variants for one sample.

    Args:
        sample: manifest row dict
        data: uint8 numpy array (full bitstream)
        output_dir: base output directory
        invert: pixel inversion flag

    Returns:
        list of metadata dicts
    """
    output_dir = output_dir or OUTPUT_DIR
    file_size = len(data)
    meta_list = []

    for variant in CASE_B_VARIANTS:
        img, window_mode, off_start, off_end = render_case_b(data, variant, invert)

        # Save image
        var_dir = os.path.join(output_dir, "case_b", variant)
        os.makedirs(var_dir, exist_ok=True)
        img_path = os.path.join(var_dir, f"{sample['sample_id']}_{variant}.png")
        img.save(img_path)

        # Save metadata
        rel_path = os.path.relpath(img_path, output_dir)
        meta = build_metadata(
            sample=sample,
            variant=variant,
            window_mode=window_mode,
            file_size=file_size,
            bytes_used=WINDOW_SIZE,
            byte_offset_start=off_start,
            byte_offset_end=off_end,
            output_path=rel_path,
            invert=invert,
        )
        write_metadata(meta, os.path.join(output_dir, "metadata"))
        meta_list.append(meta)

    return meta_list


def generate_all_case_b(manifest, output_dir=None, invert=DEFAULT_INVERT_B,
                        sample_ids=None):
    """Generate Case B images for all (or selected) samples.

    Args:
        manifest: list of manifest row dicts
        output_dir: base output directory
        invert: pixel inversion flag
        sample_ids: optional list of sample IDs to process (None = all)

    Returns:
        list of all metadata dicts
    """
    from io_utils import get_bitstream_path, read_bytes

    all_meta = []
    for sample in manifest:
        if sample_ids and sample["sample_id"] not in sample_ids:
            continue
        path = get_bitstream_path(sample)
        data = read_bytes(path)
        meta = generate_case_b_for_sample(sample, data, output_dir, invert)
        all_meta.extend(meta)
        print(f"  Case B: {sample['sample_id']} done ({len(data)} bytes)")

    return all_meta
