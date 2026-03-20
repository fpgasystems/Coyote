"""Per-image metadata writer."""

import json
import os
from config import OUTPUT_DIR


def write_metadata(params, output_dir=None):
    """Write a JSON metadata file for one generated image.

    Args:
        params: dict with keys like sample_id, variant, etc.
        output_dir: directory for metadata files (default: OUTPUT_DIR/metadata/)
    """
    output_dir = output_dir or os.path.join(OUTPUT_DIR, "metadata")
    os.makedirs(output_dir, exist_ok=True)

    fname = f"{params['sample_id']}_{params['variant']}.json"
    path = os.path.join(output_dir, fname)
    with open(path, "w") as f:
        json.dump(params, f, indent=2)
    return path


def build_metadata(sample, variant, window_mode, file_size, bytes_used,
                   byte_offset_start, byte_offset_end, output_path,
                   invert=None, normalization=None, line_width=None,
                   supersample_factor=None):
    """Build a metadata dict for one generated image."""
    return {
        "sample_id": sample["sample_id"],
        "bitstream_filename": os.path.basename(sample["bitstream_path"]),
        "bitstream_path": sample["bitstream_path"],
        "file_size_bytes": file_size,
        "variant": variant,
        "window_mode": window_mode,
        "bytes_used": bytes_used,
        "byte_offset_start": byte_offset_start,
        "byte_offset_end": byte_offset_end,
        "output_image_size": [256, 256],
        "invert": invert,
        "normalization": normalization,
        "line_width": line_width,
        "supersample_factor": supersample_factor,
        "class_label": int(sample["class_label"]),
        "base_app_id": sample["base_app_id"],
        "variant_id": sample["variant_id"],
        "region_id": int(sample["region_id"]),
        "output_path": output_path,
    }
