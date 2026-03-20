"""Case A: paper-like plotted 2D data-series images.

Four plotting variants:
  A1: index-value line plot (matplotlib Agg)
  A2: paired-point line plot (accumulation buffer)
  A3: chunked polyline plot (PIL + supersampling)
  A4: density/accumulation map (pure numpy)
"""

import os
import io
import numpy as np
from PIL import Image, ImageDraw

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from config import (
    IMG_SIZE, WINDOW_SIZE, OUTPUT_DIR, SUPERSAMPLE_FACTOR,
    DEFAULT_INVERT_A, DEFAULT_INVERT_A4, DEFAULT_A4_NORM,
    DEFAULT_LINE_WIDTH, DEFAULT_A_WINDOW, DEFAULT_A2_GAMMA, CASE_A_VARIANTS,
)
from io_utils import extract_window
from metadata import build_metadata, write_metadata


# ---------------------------------------------------------------------------
# A1: Index-value line plot (matplotlib)
# ---------------------------------------------------------------------------

def render_A1(data, window_mode=DEFAULT_A_WINDOW, invert=DEFAULT_INVERT_A,
              line_width=DEFAULT_LINE_WIDTH):
    """Index-value line plot: x=byte index, y=byte value.

    Uses matplotlib Agg backend for anti-aliased rendering.

    Returns:
        (PIL.Image 256x256, window_mode, offset_start, offset_end)
    """
    window = extract_window(data, window_mode)
    n = len(data)
    off_start, off_end = _window_offsets(n, window_mode)

    # Subsample for plotting: 65536 points is fine for matplotlib
    x = np.arange(len(window))
    y = window.astype(np.float32)

    # Create figure at exact pixel size
    dpi = 100
    fig, ax = plt.subplots(figsize=(IMG_SIZE / dpi, IMG_SIZE / dpi), dpi=dpi)

    if invert:
        bg, fg = "white", "black"
    else:
        bg, fg = "black", "white"

    fig.patch.set_facecolor(bg)
    ax.set_facecolor(bg)
    ax.plot(x, y, color=fg, linewidth=line_width * 0.3, rasterized=True)
    ax.set_xlim(0, len(window) - 1)
    ax.set_ylim(0, 255)
    ax.axis("off")
    ax.set_position([0, 0, 1, 1])  # fill entire figure

    # Render to buffer
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, pad_inches=0,
                facecolor=fig.get_facecolor(), edgecolor="none")
    plt.close(fig)
    buf.seek(0)
    img = Image.open(buf).convert("L")
    img = img.resize((IMG_SIZE, IMG_SIZE), Image.LANCZOS)

    return img, window_mode, off_start, off_end


# ---------------------------------------------------------------------------
# A2: Paired-point line plot (accumulation buffer)
# ---------------------------------------------------------------------------

def _bresenham_line(r0, c0, r1, c1):
    """Bresenham line rasterization. Returns (rows, cols) arrays."""
    r0, c0, r1, c1 = int(r0), int(c0), int(r1), int(c1)
    dr = abs(r1 - r0)
    dc = abs(c1 - c0)
    sr = 1 if r1 > r0 else -1
    sc = 1 if c1 > c0 else -1

    n = max(dr, dc) + 1
    rows = np.empty(n, dtype=np.intp)
    cols = np.empty(n, dtype=np.intp)

    r, c = r0, c0
    err = dc - dr
    for i in range(n):
        rows[i] = r
        cols[i] = c
        e2 = 2 * err
        if e2 > -dr:
            err -= dr
            c += sc
        if e2 < dc:
            err += dc
            r += sr

    return rows, cols


def render_A2(data, window_mode=DEFAULT_A_WINDOW, invert=DEFAULT_INVERT_A,
              line_width=DEFAULT_LINE_WIDTH, gamma=DEFAULT_A2_GAMMA):
    """Paired-byte coordinate line plot with depth accumulation.

    Bytes as (x,y) pairs: (b0,b1), (b2,b3), ...
    Lines connect consecutive pairs. Overlapping lines accumulate,
    producing intensity proportional to crossing density.

    Returns:
        (PIL.Image 256x256, window_mode, offset_start, offset_end)
    """
    window = extract_window(data, window_mode)
    n = len(data)
    off_start, off_end = _window_offsets(n, window_mode)

    # Build (x, y) pairs — byte values map directly to 0..255
    xs = window[0::2].astype(np.intp)
    ys = 255 - window[1::2].astype(np.intp)  # flip y so 0 is at bottom

    # Accumulate line segments on float grid
    grid = np.zeros((256, 256), dtype=np.float64)
    for i in range(len(xs) - 1):
        rr, cc = _bresenham_line(ys[i], xs[i], ys[i + 1], xs[i + 1])
        mask = (rr >= 0) & (rr < 256) & (cc >= 0) & (cc < 256)
        np.add.at(grid, (rr[mask], cc[mask]), 1)

    # Log-normalize (same approach as A4), then apply gamma
    grid = np.log1p(grid)
    if grid.max() > 0:
        grid = grid / grid.max()            # 0..1
        grid = np.power(grid, gamma)        # gamma < 1 darkens faint lines
        grid = (grid * 255).astype(np.uint8)
    else:
        grid = grid.astype(np.uint8)

    if invert:
        grid = 255 - grid

    img = Image.fromarray(grid, mode="L")
    return img, window_mode, off_start, off_end


# ---------------------------------------------------------------------------
# A3: Chunked polyline plot (PIL + supersampling)
# ---------------------------------------------------------------------------

def render_A3(data, window_mode=DEFAULT_A_WINDOW, invert=DEFAULT_INVERT_A,
              line_width=DEFAULT_LINE_WIDTH, n_chunks=256):
    """Chunked polyline: split into chunks, plot mean value per chunk.

    x = chunk index (0..n_chunks-1), y = mean byte value of chunk.
    Produces a smoothed "profile" of the byte stream.

    Returns:
        (PIL.Image 256x256, window_mode, offset_start, offset_end)
    """
    window = extract_window(data, window_mode)
    n = len(data)
    off_start, off_end = _window_offsets(n, window_mode)

    ss = SUPERSAMPLE_FACTOR
    canvas_size = IMG_SIZE * ss

    if invert:
        bg, fg = 255, 0
    else:
        bg, fg = 0, 255

    # Compute per-chunk mean
    chunk_size = len(window) // n_chunks
    trimmed = window[:chunk_size * n_chunks].reshape(n_chunks, chunk_size)
    means = trimmed.mean(axis=1)  # shape (n_chunks,)

    # Map to canvas coordinates
    xs = np.linspace(0, canvas_size - 1, n_chunks)
    ys = means * (canvas_size - 1) / 255.0
    ys = (canvas_size - 1) - ys  # flip y

    img = Image.new("L", (canvas_size, canvas_size), bg)
    draw = ImageDraw.Draw(img)
    coords = list(zip(xs.tolist(), ys.tolist()))
    if len(coords) > 1:
        draw.line(coords, fill=fg, width=line_width * ss)

    img = img.resize((IMG_SIZE, IMG_SIZE), Image.LANCZOS)
    return img, window_mode, off_start, off_end


# ---------------------------------------------------------------------------
# A4: Density / accumulation map (pure numpy)
# ---------------------------------------------------------------------------

def render_A4(data, invert=DEFAULT_INVERT_A4, normalization=DEFAULT_A4_NORM,
              clip_percentile=99.9, use_full_file=True,
              window_mode=DEFAULT_A_WINDOW):
    """Density accumulation map from byte pairs.

    Consecutive byte pairs (b_i, b_{i+1}) index into a 256x256 grid.
    Each hit increments the cell. Normalized and converted to grayscale.

    Returns:
        (PIL.Image 256x256, window_mode, offset_start, offset_end)
    """
    n = len(data)

    if use_full_file:
        source = data
        off_start, off_end = 0, n
        wm = "full"
    else:
        source = extract_window(data, window_mode)
        off_start, off_end = _window_offsets(n, window_mode)
        wm = window_mode

    # Build pairs: (x, y) = (byte_i, byte_{i+1})
    x = source[:-1]
    y = source[1:]

    # Accumulate on 256x256 grid
    grid = np.zeros((256, 256), dtype=np.float64)
    np.add.at(grid, (y.astype(np.intp), x.astype(np.intp)), 1)

    # Normalize
    if normalization == "log":
        grid = np.log1p(grid)
    elif normalization == "log_clip":
        grid = np.log1p(grid)
        if grid.max() > 0:
            thresh = np.percentile(grid[grid > 0], clip_percentile)
            grid = np.clip(grid, 0, thresh)
    elif normalization == "linear":
        pass
    else:
        raise ValueError(f"Unknown normalization: {normalization}")

    # Scale to 0-255
    if grid.max() > 0:
        grid = (grid / grid.max() * 255).astype(np.uint8)
    else:
        grid = grid.astype(np.uint8)

    if invert:
        grid = 255 - grid

    img = Image.fromarray(grid, mode="L")
    return img, wm, off_start, off_end


# ---------------------------------------------------------------------------
# Dispatch and batch generation
# ---------------------------------------------------------------------------

def render_case_a(data, variant, **kwargs):
    """Dispatch to the correct Case A renderer.

    Returns:
        (PIL.Image 256x256, window_mode, offset_start, offset_end)
    """
    renderers = {
        "A1": render_A1,
        "A2": render_A2,
        "A3": render_A3,
        "A4": render_A4,
    }
    return renderers[variant](data, **kwargs)


def generate_case_a_for_sample(sample, data, output_dir=None,
                               variants=None, **kwargs):
    """Generate Case A images for one sample.

    Returns:
        list of metadata dicts
    """
    output_dir = output_dir or OUTPUT_DIR
    variants = variants or CASE_A_VARIANTS
    file_size = len(data)
    meta_list = []

    for variant in variants:
        img, wm, off_start, off_end = render_case_a(data, variant, **kwargs)

        # Save image
        var_dir = os.path.join(output_dir, "case_a", variant)
        os.makedirs(var_dir, exist_ok=True)
        img_path = os.path.join(var_dir, f"{sample['sample_id']}_{variant}.png")
        img.save(img_path)

        # Compute bytes_used
        if variant == "A4" and kwargs.get("use_full_file", True):
            bytes_used = file_size
        else:
            bytes_used = WINDOW_SIZE

        rel_path = os.path.relpath(img_path, output_dir)
        meta = build_metadata(
            sample=sample,
            variant=variant,
            window_mode=wm,
            file_size=file_size,
            bytes_used=bytes_used,
            byte_offset_start=off_start,
            byte_offset_end=off_end,
            output_path=rel_path,
            invert=kwargs.get("invert"),
            normalization=kwargs.get("normalization") if variant == "A4" else None,
            line_width=kwargs.get("line_width", DEFAULT_LINE_WIDTH),
            supersample_factor=SUPERSAMPLE_FACTOR if variant == "A3" else None,
        )
        write_metadata(meta, os.path.join(output_dir, "metadata"))
        meta_list.append(meta)

    return meta_list


def generate_all_case_a(manifest, output_dir=None, sample_ids=None,
                        variants=None, **kwargs):
    """Generate Case A images for all (or selected) samples.

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
        meta = generate_case_a_for_sample(sample, data, output_dir,
                                          variants, **kwargs)
        all_meta.extend(meta)
        vs = ",".join(variants or CASE_A_VARIANTS)
        print(f"  Case A [{vs}]: {sample['sample_id']} done")

    return all_meta


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _window_offsets(n, window_mode):
    """Compute (start, end) byte offsets for a given window mode."""
    if n <= WINDOW_SIZE:
        return 0, n
    if window_mode == "first":
        return 0, WINDOW_SIZE
    elif window_mode == "last":
        return n - WINDOW_SIZE, n
    elif window_mode == "center":
        mid = n // 2
        half = WINDOW_SIZE // 2
        return mid - half, mid - half + WINDOW_SIZE
    elif window_mode == "downsample":
        return 0, n
    elif window_mode == "full":
        return 0, n
    return 0, n
