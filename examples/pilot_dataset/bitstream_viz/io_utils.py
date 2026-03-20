"""I/O utilities: manifest parsing, bitstream reading, window extraction."""

import csv
import os
import numpy as np
from config import BITSTREAM_DIR, MANIFEST_PATH, WINDOW_SIZE


def load_manifest(path=None):
    """Parse the pilot manifest CSV. Returns list of dicts (one per sample)."""
    path = path or MANIFEST_PATH
    with open(path, "r") as f:
        reader = csv.DictReader(f)
        rows = []
        for row in reader:
            # Strip whitespace from keys and values
            cleaned = {k.strip(): v.strip() for k, v in row.items()}
            rows.append(cleaned)
    return rows


def get_bitstream_path(sample, bitstream_dir=None):
    """Resolve full filesystem path from a manifest row."""
    bitstream_dir = bitstream_dir or BITSTREAM_DIR
    return os.path.join(bitstream_dir, sample["bitstream_path"])


def read_bytes(path):
    """Read entire file as a uint8 numpy array."""
    return np.fromfile(path, dtype=np.uint8)


def extract_window(data, mode, window_size=WINDOW_SIZE):
    """Extract a fixed-size byte window from a uint8 array.

    Args:
        data: uint8 numpy array (the full bitstream)
        mode: one of "first", "last", "center", "downsample"
        window_size: number of bytes to extract (default 65536)

    Returns:
        uint8 numpy array of exactly window_size bytes.
        Zero-padded if data is shorter than window_size.
    """
    n = len(data)

    if n <= window_size:
        # Zero-pad
        out = np.zeros(window_size, dtype=np.uint8)
        out[:n] = data
        return out

    if mode == "first":
        return data[:window_size].copy()

    elif mode == "last":
        return data[-window_size:].copy()

    elif mode == "center":
        mid = n // 2
        half = window_size // 2
        start = mid - half
        return data[start:start + window_size].copy()

    elif mode == "downsample":
        indices = np.linspace(0, n - 1, window_size, dtype=np.int64)
        return data[indices]

    else:
        raise ValueError(f"Unknown window mode: {mode}")
