#!/usr/bin/env python3
"""Preliminary bitstream visualization for full dataset iteration 1.

Reuses the pilot rendering functions (Case B grayscale, Case A line/density plots)
but with montages designed for the 2-class (benign vs standalone) full dataset.

Usage:
    python3 run_viz.py                  # all available samples, all 8 variants + montages
    python3 run_viz.py --case-b-only    # Case B only
    python3 run_viz.py --case-a-only    # Case A only
    python3 run_viz.py --no-montage     # skip montage generation
"""

import argparse
import csv
import os
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
BUILDS_DIR = "/mnt/scratch/sdeheredia/Coyote/examples/full_dataset_it1/builds"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST_PATH = os.path.join(SCRIPT_DIR, "prelim_manifest.csv")
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output")

IMG_SIZE = 256
CASE_B_VARIANTS = ["B1", "B2", "B3", "B4"]
CASE_A_VARIANTS = ["A1", "A2", "A3", "A4"]
ALL_VARIANTS = CASE_B_VARIANTS + CASE_A_VARIANTS

# Montage layout
CELL_SIZE = 256
LABEL_HEIGHT = 24
HEADER_WIDTH = 160
PADDING = 2


def load_manifest(path=None):
    path = path or MANIFEST_PATH
    with open(path, "r") as f:
        reader = csv.DictReader(f)
        return [dict(row) for row in reader]


def get_bitstream_path(sample):
    return os.path.join(BUILDS_DIR, sample["bitstream_path"])


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
        print(f"  SKIP {sample['sample_id']}: file not found at {path}")
        return []

    data = read_bytes(path)
    sid = sample["sample_id"]
    meta_list = []

    for variant in variants:
        if variant.startswith("B"):
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


def create_montage(rows, variants, output_dir, output_path, row_label_fn=None):
    """Generic montage: rows=samples, columns=variants."""
    font = get_font()
    n_rows = len(rows)
    n_cols = len(variants)

    w = HEADER_WIDTH + n_cols * (CELL_SIZE + PADDING) + PADDING
    h = LABEL_HEIGHT + n_rows * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    # Column headers
    for j, var in enumerate(variants):
        x = HEADER_WIDTH + PADDING + j * (CELL_SIZE + PADDING)
        draw.text((x + CELL_SIZE // 2 - 12, 4), var, fill=0, font=font)

    # Rows
    for i, row in enumerate(rows):
        y = LABEL_HEIGHT + PADDING + i * (CELL_SIZE + PADDING)
        sid = row["sample_id"]

        if row_label_fn:
            label = row_label_fn(row)
        else:
            label = f"{sid}\n{row.get('base_app_id', '')[:16]}"

        for li, line in enumerate(label.split("\n")):
            draw.text((4, y + 4 + li * 14), line, fill=0, font=font)

        for j, var in enumerate(variants):
            x = HEADER_WIDTH + PADDING + j * (CELL_SIZE + PADDING)
            img_path = find_image(sid, var, output_dir)
            if img_path:
                cell = Image.open(img_path).convert("L")
                canvas.paste(cell, (x, y))
            else:
                draw.rectangle([x, y, x + CELL_SIZE, y + CELL_SIZE], outline=0, width=1)
                draw.line([x, y, x + CELL_SIZE, y + CELL_SIZE], fill=0)
                draw.line([x + CELL_SIZE, y, x, y + CELL_SIZE], fill=0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


def create_interleaved_montage(benign_rows, stand_rows, variants, output_dir, output_path):
    """Side-by-side comparison: for each variant column, show benign then standalone.

    Rows alternate: benign sample, then its "matched" standalone sample.
    Actually: columns are Var_Ben, Var_Stand for each variant.
    """
    font = get_font()
    n_pairs = min(len(benign_rows), len(stand_rows))
    n_cols = len(variants) * 2  # Ben + Stand for each variant

    row_header_w = 160
    col_header_h = 28
    w = row_header_w + n_cols * (CELL_SIZE + PADDING) + PADDING
    h = col_header_h + n_pairs * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    # Column headers
    for vi, var in enumerate(variants):
        for ci, cls_label in enumerate(["Ben", "Stand"]):
            x = row_header_w + PADDING + (vi * 2 + ci) * (CELL_SIZE + PADDING)
            draw.text((x + CELL_SIZE // 2 - 24, 6), f"{var} {cls_label}",
                      fill=0, font=font)

    for i in range(n_pairs):
        y = col_header_h + PADDING + i * (CELL_SIZE + PADDING)
        b = benign_rows[i]
        s = stand_rows[i]

        # Row labels
        draw.text((4, y + 4),  f"Ben: {b['base_app_id'][:14]}", fill=0, font=font)
        draw.text((4, y + 18), f"  {int(b['lut_count']):,} LUTs", fill=80, font=font)
        ro_count = int(s.get("ro_count", 0))
        draw.text((4, y + 36), f"Std: ro_{ro_count}", fill=0, font=font)
        draw.text((4, y + 50), f"  {int(s['lut_count']):,} LUTs", fill=80, font=font)

        for vi, var in enumerate(variants):
            # Benign cell
            bp = find_image(b["sample_id"], var, output_dir)
            if bp:
                x = row_header_w + PADDING + (vi * 2) * (CELL_SIZE + PADDING)
                canvas.paste(Image.open(bp).convert("L"), (x, y))
            # Standalone cell
            sp = find_image(s["sample_id"], var, output_dir)
            if sp:
                x = row_header_w + PADDING + (vi * 2 + 1) * (CELL_SIZE + PADDING)
                canvas.paste(Image.open(sp).convert("L"), (x, y))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


# --- Montage generation ---

def generate_all_montages(manifest, output_dir):
    """Generate all montages for the preliminary full dataset."""
    paths = []
    benign = [r for r in manifest if r["class_label"] == "0"]
    stand = [r for r in manifest if r["class_label"] == "1"]

    montage_dir = os.path.join(output_dir, "montages")

    # 1. All benign samples, all 8 variants
    print("  Montage: all benign (15 samples x 8 variants)...")
    def benign_label(r):
        return f"{r['sample_id']} {r['app_id']}\n{r['base_app_id'][:16]}\n{int(r['lut_count']):,} LUTs"
    p = create_montage(benign, ALL_VARIANTS, output_dir,
                       os.path.join(montage_dir, "all_benign_8var.png"),
                       row_label_fn=benign_label)
    paths.append(p)

    # 2. All standalone samples, all 8 variants
    print("  Montage: all standalone (14 samples x 8 variants)...")
    def stand_label(r):
        ro = int(r.get("ro_count", 0))
        return f"{r['sample_id']} RO={ro}\n{int(r['lut_count']):,} LUTs"
    p = create_montage(stand, ALL_VARIANTS, output_dir,
                       os.path.join(montage_dir, "all_standalone_8var.png"),
                       row_label_fn=stand_label)
    paths.append(p)

    # 3. Standalone RO progression (A4 density — most informative for RO scaling)
    print("  Montage: standalone RO progression (A4 density)...")
    p = create_montage(stand, ["A4"], output_dir,
                       os.path.join(montage_dir, "standalone_A4_progression.png"),
                       row_label_fn=stand_label)
    paths.append(p)

    # 4. Standalone RO progression (B4 downsample)
    print("  Montage: standalone RO progression (B4 downsample)...")
    p = create_montage(stand, ["B4"], output_dir,
                       os.path.join(montage_dir, "standalone_B4_progression.png"),
                       row_label_fn=stand_label)
    paths.append(p)

    # 5. Side-by-side benign vs standalone (Case A variants) — ALL 15
    print(f"  Montage: benign vs standalone (Case A, {len(benign)} x {len(stand)})...")
    p = create_interleaved_montage(
        benign, stand, CASE_A_VARIANTS, output_dir,
        os.path.join(montage_dir, "benign_vs_standalone_caseA.png"))
    paths.append(p)

    # 6. Side-by-side benign vs standalone (Case B variants) — ALL 15
    print(f"  Montage: benign vs standalone (Case B, {len(benign)} x {len(stand)})...")
    p = create_interleaved_montage(
        benign, stand, CASE_B_VARIANTS, output_dir,
        os.path.join(montage_dir, "benign_vs_standalone_caseB.png"))
    paths.append(p)

    # 7. Benign vs high-RO standalone (pick 3 smallest + 3 largest RO)
    print("  Montage: benign vs high-RO standalone (A4 + B4)...")
    stand_sorted = sorted(stand, key=lambda r: int(r.get("ro_count", 0)))
    extremes = stand_sorted[:3] + stand_sorted[-3:]
    p = create_montage(benign[:6] + extremes, ["B4", "A4"], output_dir,
                       os.path.join(montage_dir, "benign_vs_extremeRO_B4A4.png"),
                       row_label_fn=lambda r: (
                           f"{r['sample_id']} {r.get('app_id', '')}\n"
                           f"{r['base_app_id'][:14]}\n"
                           f"{int(r['lut_count']):,} LUTs"
                           + (f" RO={int(r['ro_count'])}" if int(r.get('ro_count', 0)) > 0 else "")
                       ))
    paths.append(p)

    # 8. All 29 samples, just B4 + A4 (compact overview)
    print("  Montage: full overview (29 samples x B4+A4)...")
    all_samples = benign + stand
    def full_label(r):
        cls = "BEN" if r["class_label"] == "0" else "STD"
        ro = int(r.get("ro_count", 0))
        extra = f" RO={ro}" if ro > 0 else ""
        return f"{r['sample_id']} [{cls}]\n{r['base_app_id'][:14]}{extra}\n{int(r['lut_count']):,} LUTs"
    p = create_montage(all_samples, ["B4", "A4"], output_dir,
                       os.path.join(montage_dir, "full_overview_B4_A4.png"),
                       row_label_fn=full_label)
    paths.append(p)

    return paths


# --- Main ---

def main():
    parser = argparse.ArgumentParser(description="Full dataset preliminary bitstream visualization")
    parser.add_argument("--case-b-only", action="store_true")
    parser.add_argument("--case-a-only", action="store_true")
    parser.add_argument("--no-montage", action="store_true")
    parser.add_argument("--montage-only", action="store_true",
                        help="Skip image generation, only build montages")
    parser.add_argument("--output-dir", default=OUTPUT_DIR)
    parser.add_argument("--manifest", default=MANIFEST_PATH)
    args = parser.parse_args()

    if args.case_b_only:
        variants = CASE_B_VARIANTS
    elif args.case_a_only:
        variants = CASE_A_VARIANTS
    else:
        variants = ALL_VARIANTS

    manifest = load_manifest(args.manifest)
    print(f"Loaded manifest: {len(manifest)} samples")
    print(f"  Benign: {sum(1 for r in manifest if r['class_label'] == '0')}")
    print(f"  Standalone: {sum(1 for r in manifest if r['class_label'] == '1')}")
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
            if (i + 1) % 5 == 0 or i == len(manifest) - 1:
                print(f"  Progress: {i+1}/{len(manifest)} samples, {total_imgs} images")
        print(f"\nGenerated {total_imgs} images in {time.time()-t0:.1f}s")
    else:
        print("Skipping image generation (--montage-only)")

    # Montages
    if not args.no_montage:
        print("\n=== Montages ===")
        t_montage = time.time()
        paths = generate_all_montages(manifest, args.output_dir)
        print(f"\nGenerated {len(paths)} montages in {time.time()-t_montage:.1f}s")
        for p in paths:
            print(f"  {os.path.relpath(p, args.output_dir)}")

    elapsed = time.time() - t0
    print(f"\nTotal time: {elapsed:.1f}s")

    # Count output files
    n_png = sum(1 for r, d, fs in os.walk(args.output_dir) for f in fs if f.endswith(".png"))
    print(f"Output: {n_png} PNG files in {args.output_dir}")


if __name__ == "__main__":
    main()
