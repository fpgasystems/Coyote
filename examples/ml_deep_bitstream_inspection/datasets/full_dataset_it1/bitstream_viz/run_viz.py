#!/usr/bin/env python3
"""Bitstream visualization for full dataset iteration 1 (150 samples).

Reuses the pilot rendering functions (Case B grayscale, Case A line/density plots)
with montages designed for the 2-class, 5-floorplan full dataset.

Usage:
    python3 run_viz.py                  # all 150 samples, all 8 variants + montages
    python3 run_viz.py --case-b-only    # Case B only
    python3 run_viz.py --case-a-only    # Case A only
    python3 run_viz.py --hires-only     # hi-res B4 variants only (512, 1024, 2048)
    python3 run_viz.py --no-montage     # skip montage generation
    python3 run_viz.py --montage-only   # regenerate montages from existing images
"""

import argparse
import csv
import os
import re
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Add pilot viz to path for reuse of rendering functions
PILOT_VIZ_DIR = "/mnt/scratch/sdeheredia/Coyote/examples/pilot_dataset/bitstream_viz"
sys.path.insert(0, PILOT_VIZ_DIR)

from case_b import render_case_b
from case_a import render_case_a
from io_utils import read_bytes

# --- Constants ---
DATASET_DIR = "/mnt/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/datasets/full_dataset_it1"
ARTIFACTS_DIR = os.path.join(DATASET_DIR, "artifacts")
BITSTREAM_DIR = os.path.join(ARTIFACTS_DIR, "bitstreams")
MANIFEST_PATH = os.path.join(ARTIFACTS_DIR, "manifest.csv")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output_full")

IMG_SIZE = 256
CASE_B_VARIANTS = ["B1", "B2", "B3", "B4"]
CASE_A_VARIANTS = ["A1", "A2", "A3", "A4"]
HIRES_VARIANTS = ["B4_512", "B4_1024", "B4_2048"]
ALL_VARIANTS = CASE_B_VARIANTS + CASE_A_VARIANTS
ALL_VARIANTS_WITH_HIRES = ALL_VARIANTS + HIRES_VARIANTS
FLOORPLANS = ["FP00", "FP01", "FP02", "FP03", "FP04"]

# Montage layout
CELL_SIZE = 256
LABEL_HEIGHT = 24
HEADER_WIDTH = 180
PADDING = 2


# --- Hi-res B4 rendering ---

def _parse_b4_size(variant):
    """Extract image size from a B4_NNN variant name. Returns None if not a hires variant."""
    m = re.match(r"B4_(\d+)", variant)
    return int(m.group(1)) if m else None


def render_b4_hires(data, img_size, invert=True):
    """Render B4 (downsample) at arbitrary resolution."""
    window_size = img_size * img_size
    n = len(data)
    if n <= window_size:
        window = np.zeros(window_size, dtype=np.uint8)
        window[:n] = data
    else:
        indices = np.linspace(0, n - 1, window_size, dtype=np.int64)
        window = data[indices]
    if invert:
        pixels = (255 - window).astype(np.uint8)
    else:
        pixels = window
    return Image.fromarray(pixels.reshape(img_size, img_size), mode="L")


def load_manifest(path=None):
    path = path or MANIFEST_PATH
    with open(path, "r") as f:
        reader = csv.DictReader(f)
        return [dict(row) for row in reader]


def get_bitstream_path(sample):
    return os.path.join(BITSTREAM_DIR, sample["bitstream_path"])


def get_font():
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11)
    except (IOError, OSError):
        return ImageFont.load_default()


# --- Per-sample image generation ---

def generate_images_for_sample(sample, output_dir, variants):
    """Generate all requested variant images for one sample."""
    path = get_bitstream_path(sample)
    if not os.path.isfile(path):
        print(f"  SKIP {sample['sample_id']}: not found at {path}")
        return []

    data = read_bytes(path)
    sid = sample["sample_id"]
    meta_list = []

    for variant in variants:
        hires_size = _parse_b4_size(variant)
        if hires_size:
            img = render_b4_hires(data, hires_size)
            subdir = os.path.join(output_dir, "case_b", variant)
        elif variant.startswith("B"):
            img, wm, off_s, off_e = render_case_b(data, variant)
            subdir = os.path.join(output_dir, "case_b", variant)
        else:
            img, wm, off_s, off_e = render_case_a(data, variant)
            subdir = os.path.join(output_dir, "case_a", variant)

        os.makedirs(subdir, exist_ok=True)
        img_path = os.path.join(subdir, f"{sid}_{variant}.png")
        img.save(img_path)
        meta_list.append({"sample_id": sid, "variant": variant, "path": img_path})

    return meta_list


# --- Montage helpers ---

def find_image(sample_id, variant, output_dir):
    if variant.startswith("B"):
        subdir = os.path.join(output_dir, "case_b", variant)
    else:
        subdir = os.path.join(output_dir, "case_a", variant)
    path = os.path.join(subdir, f"{sample_id}_{variant}.png")
    return path if os.path.exists(path) else None


def create_montage(rows, variants, output_dir, output_path, row_label_fn=None, cell_size=CELL_SIZE):
    """Generic montage: rows=samples, columns=variants."""
    font = get_font()
    n_rows = len(rows)
    n_cols = len(variants)

    w = HEADER_WIDTH + n_cols * (cell_size + PADDING) + PADDING
    h = LABEL_HEIGHT + n_rows * (cell_size + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    for j, var in enumerate(variants):
        x = HEADER_WIDTH + PADDING + j * (cell_size + PADDING)
        draw.text((x + cell_size // 2 - 12, 4), var, fill=0, font=font)

    for i, row in enumerate(rows):
        y = LABEL_HEIGHT + PADDING + i * (cell_size + PADDING)
        sid = row["sample_id"]

        label = row_label_fn(row) if row_label_fn else f"{sid}\n{row.get('app_name', '')[:16]}"
        for li, line in enumerate(label.split("\n")):
            draw.text((4, y + 4 + li * 14), line, fill=0, font=font)

        for j, var in enumerate(variants):
            x = HEADER_WIDTH + PADDING + j * (cell_size + PADDING)
            img_path = find_image(sid, var, output_dir)
            if img_path:
                cell_img = Image.open(img_path).convert("L")
                if cell_img.size != (cell_size, cell_size):
                    cell_img = cell_img.resize((cell_size, cell_size), Image.LANCZOS)
                canvas.paste(cell_img, (x, y))
            else:
                draw.rectangle([x, y, x + cell_size, y + cell_size], outline=0, width=1)
                draw.line([x, y, x + cell_size, y + cell_size], fill=0)
                draw.line([x + cell_size, y, x, y + cell_size], fill=0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


def create_interleaved_montage(benign_rows, stand_rows, variants, output_dir, output_path,
                               benign_label_fn=None, stand_label_fn=None):
    """Side-by-side: columns are Var_Ben, Var_Stand for each variant."""
    font = get_font()
    n_pairs = min(len(benign_rows), len(stand_rows))
    n_cols = len(variants) * 2

    row_header_w = 180
    col_header_h = 28
    w = row_header_w + n_cols * (CELL_SIZE + PADDING) + PADDING
    h = col_header_h + n_pairs * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    for vi, var in enumerate(variants):
        for ci, cls_label in enumerate(["Ben", "Stand"]):
            x = row_header_w + PADDING + (vi * 2 + ci) * (CELL_SIZE + PADDING)
            draw.text((x + CELL_SIZE // 2 - 24, 6), f"{var} {cls_label}",
                      fill=0, font=font)

    for i in range(n_pairs):
        y = col_header_h + PADDING + i * (CELL_SIZE + PADDING)
        b = benign_rows[i]
        s = stand_rows[i]

        if benign_label_fn:
            bl = benign_label_fn(b)
        else:
            bl = f"Ben: {b['app_name'][:14]}"
        if stand_label_fn:
            sl = stand_label_fn(s)
        else:
            ro = int(s.get("ro_count", 0))
            sl = f"Std: ro_{ro}"

        for li, line in enumerate(bl.split("\n")):
            draw.text((4, y + 4 + li * 14), line, fill=0, font=font)
        y_offset = len(bl.split("\n")) * 14 + 4
        for li, line in enumerate(sl.split("\n")):
            draw.text((4, y + y_offset + li * 14), line, fill=80, font=font)

        for vi, var in enumerate(variants):
            bp = find_image(b["sample_id"], var, output_dir)
            if bp:
                x = row_header_w + PADDING + (vi * 2) * (CELL_SIZE + PADDING)
                canvas.paste(Image.open(bp).convert("L"), (x, y))
            sp = find_image(s["sample_id"], var, output_dir)
            if sp:
                x = row_header_w + PADDING + (vi * 2 + 1) * (CELL_SIZE + PADDING)
                canvas.paste(Image.open(sp).convert("L"), (x, y))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


def create_hires_montage(rows, variant, output_dir, output_path, row_label_fn=None):
    """Montage for hi-res variants — cells at native resolution."""
    font = get_font()
    n_rows = len(rows)
    cell = _parse_b4_size(variant) or CELL_SIZE

    header_w = 200
    label_h = 28
    w = header_w + cell + PADDING * 2
    h = label_h + n_rows * (cell + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)
    draw.text((header_w + cell // 2 - 20, 4), variant, fill=0, font=font)

    for i, row in enumerate(rows):
        y = label_h + PADDING + i * (cell + PADDING)
        sid = row["sample_id"]
        label = row_label_fn(row) if row_label_fn else sid
        for li, line in enumerate(label.split("\n")):
            draw.text((4, y + 4 + li * 14), line, fill=0, font=font)

        img_path = find_image(sid, variant, output_dir)
        if img_path:
            canvas.paste(Image.open(img_path).convert("L"), (header_w + PADDING, y))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


def create_hires_comparison_montage(benign_rows, stand_rows, variant, output_dir, output_path):
    """Side-by-side benign vs standalone at native resolution for a single variant."""
    font = get_font()
    cell = _parse_b4_size(variant) or CELL_SIZE

    n_pairs = min(len(benign_rows), len(stand_rows))
    header_w = 200
    col_header_h = 28
    w = header_w + 2 * cell + 3 * PADDING
    h = col_header_h + n_pairs * (cell + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    x_ben = header_w + PADDING
    x_std = header_w + PADDING + cell + PADDING
    draw.text((x_ben + cell // 2 - 40, 6), f"{variant} Benign", fill=0, font=font)
    draw.text((x_std + cell // 2 - 50, 6), f"{variant} Standalone", fill=0, font=font)

    for i in range(n_pairs):
        y = col_header_h + PADDING + i * (cell + PADDING)
        b = benign_rows[i]
        s = stand_rows[i]

        draw.text((4, y + 4), f"{b['app_id']} {b['app_name'][:12]}", fill=0, font=font)
        ro = int(s.get("ro_count", 0))
        draw.text((4, y + 20), f"RO={ro:,}", fill=80, font=font)

        bp = find_image(b["sample_id"], variant, output_dir)
        if bp:
            canvas.paste(Image.open(bp).convert("L"), (x_ben, y))
        sp = find_image(s["sample_id"], variant, output_dir)
        if sp:
            canvas.paste(Image.open(sp).convert("L"), (x_std, y))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


# --- Label helpers ---

def benign_label(r):
    fp = r.get("floorplan_id", "")
    return f"{r['sample_id']} [{fp}]\n{r['app_id']} {r['app_name'][:14]}\n{r['source_type']}"

def stand_label(r):
    ro = int(r.get("ro_count", 0))
    fp = r.get("floorplan_id", "")
    return f"{r['sample_id']} [{fp}]\nRO={ro:,}"

def full_label(r):
    cls = "BEN" if r["class_label"] == "0" else "STD"
    fp = r.get("floorplan_id", "")
    ro = int(r.get("ro_count", 0))
    if cls == "STD":
        return f"{r['sample_id']} [{cls}] {fp}\nRO={ro:,}"
    else:
        return f"{r['sample_id']} [{cls}] {fp}\n{r['app_name'][:16]}"


# --- Montage generation ---

def generate_all_montages(manifest, output_dir, floorplan="FP00"):
    """Generate simplified montages: benign vs standalone comparisons only.

    Two sets, both for a single floorplan (default FP00):
      1. B4 at multiple resolutions (256, 512, 1024, 2048)
      2. Case A + B4 (A1, A2, A3, A4, B4)
    """
    paths = []
    benign = [r for r in manifest if r["class_label"] == "0" and r["floorplan_id"] == floorplan]
    stand = [r for r in manifest if r["class_label"] == "1" and r["floorplan_id"] == floorplan]
    montage_dir = os.path.join(output_dir, "montages")

    print(f"  Floorplan: {floorplan} — {len(benign)} benign, {len(stand)} standalone")

    # ── Set 1: Benign vs standalone — B4 at each resolution ──

    for var in ["B4", "B4_512", "B4_1024", "B4_2048"]:
        print(f"  Montage: benign vs standalone {floorplan} ({var})...")
        p = create_hires_comparison_montage(
            benign, stand, var, output_dir,
            os.path.join(montage_dir, f"benign_vs_standalone_{floorplan}_{var}.png"))
        paths.append(p)

    # ── Set 2: Benign vs standalone — Case A + B4 ──

    print(f"  Montage: benign vs standalone {floorplan} (Case A + B4)...")
    p = create_interleaved_montage(
        benign, stand, ["A1", "A2", "A3", "A4", "B4"], output_dir,
        os.path.join(montage_dir, f"benign_vs_standalone_{floorplan}_caseA_B4.png"),
        benign_label_fn=lambda r: f"{r['app_id']} {r['app_name'][:12]}",
        stand_label_fn=lambda r: f"RO={int(r.get('ro_count',0)):,}")
    paths.append(p)

    return paths


# --- Main ---

def main():
    parser = argparse.ArgumentParser(description="Full dataset bitstream visualization (150 samples)")
    parser.add_argument("--case-b-only", action="store_true")
    parser.add_argument("--case-a-only", action="store_true")
    parser.add_argument("--hires-only", action="store_true",
                        help="Generate only hi-res B4 variants (512, 1024, 2048)")
    parser.add_argument("--no-montage", action="store_true")
    parser.add_argument("--montage-only", action="store_true",
                        help="Skip image generation, only build montages")
    parser.add_argument("--floorplan", default="FP00",
                        help="Floorplan for montages (default: FP00)")
    parser.add_argument("--output-dir", default=OUTPUT_DIR)
    parser.add_argument("--manifest", default=MANIFEST_PATH)
    args = parser.parse_args()

    if args.hires_only:
        variants = HIRES_VARIANTS
    elif args.case_b_only:
        variants = CASE_B_VARIANTS
    elif args.case_a_only:
        variants = CASE_A_VARIANTS
    else:
        variants = ALL_VARIANTS_WITH_HIRES

    manifest = load_manifest(args.manifest)
    n_benign = sum(1 for r in manifest if r["class_label"] == "0")
    n_stand = sum(1 for r in manifest if r["class_label"] == "1")
    fps = sorted(set(r["floorplan_id"] for r in manifest))

    print(f"Loaded manifest: {len(manifest)} samples")
    print(f"  Benign: {n_benign}, Standalone: {n_stand}")
    print(f"  Floorplans: {', '.join(fps)}")
    print(f"Variants: {', '.join(variants)}")
    print(f"Output: {args.output_dir}")
    print()

    t0 = time.time()

    # Generate per-sample images
    if not args.montage_only:
        total_imgs = 0
        for i, sample in enumerate(manifest):
            meta = generate_images_for_sample(sample, args.output_dir, variants)
            total_imgs += len(meta)
            if (i + 1) % 10 == 0 or i == len(manifest) - 1:
                elapsed = time.time() - t0
                rate = (i + 1) / elapsed
                eta = (len(manifest) - i - 1) / rate
                print(f"  Progress: {i+1}/{len(manifest)} samples, "
                      f"{total_imgs} images ({elapsed:.0f}s elapsed, ~{eta:.0f}s remaining)")
        print(f"\nGenerated {total_imgs} images in {time.time()-t0:.1f}s")
    else:
        print("Skipping image generation (--montage-only)")

    # Montages
    if not args.no_montage:
        print("\n=== Montages ===")
        t_montage = time.time()
        paths = generate_all_montages(manifest, args.output_dir, floorplan=args.floorplan)
        print(f"\nGenerated {len(paths)} montages in {time.time()-t_montage:.1f}s")
        for p in paths:
            print(f"  {os.path.relpath(p, args.output_dir)}")

    elapsed = time.time() - t0
    print(f"\nTotal time: {elapsed:.1f}s")

    n_png = sum(1 for r, d, fs in os.walk(args.output_dir) for f in fs if f.endswith(".png"))
    print(f"Output: {n_png} PNG files in {args.output_dir}")


if __name__ == "__main__":
    main()
