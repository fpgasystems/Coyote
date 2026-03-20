"""Comparison montage generation.

Creates grid-layout contact sheets for visual inspection of
bitstream-to-image mappings across samples and variants.
"""

import os
from PIL import Image, ImageDraw, ImageFont

from config import (
    IMG_SIZE, OUTPUT_DIR, ALL_VARIANTS, CASE_B_VARIANTS, CASE_A_VARIANTS,
    PILOT_SUBSET,
)


# Layout constants
CELL_SIZE = IMG_SIZE  # 256 px per thumbnail
LABEL_HEIGHT = 20     # px for text labels
HEADER_WIDTH = 120    # px for row headers
PADDING = 2           # px between cells


def _get_font():
    """Get a bitmap font (no TTF dependency)."""
    return ImageFont.load_default()


def _find_image(sample_id, variant, output_dir):
    """Locate a generated image file."""
    if variant.startswith("B"):
        subdir = os.path.join(output_dir, "case_b", variant)
    else:
        subdir = os.path.join(output_dir, "case_a", variant)
    path = os.path.join(subdir, f"{sample_id}_{variant}.png")
    if os.path.exists(path):
        return path
    return None


def create_montage(sample_ids, variants, output_dir=None, output_path=None,
                   manifest=None):
    """Create a grid montage: rows=samples, columns=variants.

    Args:
        sample_ids: list of sample IDs for rows
        variants: list of variant names for columns
        output_dir: base output directory (where case_a/, case_b/ live)
        output_path: path for the output montage image
        manifest: optional manifest for richer row labels

    Returns:
        path to saved montage
    """
    output_dir = output_dir or OUTPUT_DIR
    output_path = output_path or os.path.join(output_dir, "montages",
                                               "comparison.png")

    n_rows = len(sample_ids)
    n_cols = len(variants)
    font = _get_font()

    # Compute canvas size
    w = HEADER_WIDTH + n_cols * (CELL_SIZE + PADDING) + PADDING
    h = LABEL_HEIGHT + n_rows * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)  # light gray background
    draw = ImageDraw.Draw(canvas)

    # Build lookup for manifest info
    sample_info = {}
    if manifest:
        for row in manifest:
            sample_info[row["sample_id"]] = row

    # Column headers
    for j, var in enumerate(variants):
        x = HEADER_WIDTH + PADDING + j * (CELL_SIZE + PADDING)
        draw.text((x + CELL_SIZE // 2 - 10, 2), var, fill=0, font=font)

    # Rows
    for i, sid in enumerate(sample_ids):
        y = LABEL_HEIGHT + PADDING + i * (CELL_SIZE + PADDING)

        # Row label
        label = sid
        if sid in sample_info:
            info = sample_info[sid]
            cls = ["ben", "sus", "std"][int(info["class_label"])]
            label = f"{sid} {cls}\n{info['base_app_id'][:12]}\nreg{info['region_id']}"

        # Draw multiline label
        for li, line in enumerate(label.split("\n")):
            draw.text((4, y + li * 12), line, fill=0, font=font)

        # Cells
        for j, var in enumerate(variants):
            x = HEADER_WIDTH + PADDING + j * (CELL_SIZE + PADDING)
            img_path = _find_image(sid, var, output_dir)
            if img_path:
                cell = Image.open(img_path).convert("L")
                canvas.paste(cell, (x, y))
            else:
                # Missing: draw X
                draw.rectangle([x, y, x + CELL_SIZE, y + CELL_SIZE],
                               outline=0, width=1)
                draw.line([x, y, x + CELL_SIZE, y + CELL_SIZE], fill=0)
                draw.line([x + CELL_SIZE, y, x, y + CELL_SIZE], fill=0)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    canvas.save(output_path)
    return output_path


def create_pair_comparison(benign_id, suspicious_id, app_name, variants=None,
                           output_dir=None, output_path=None, manifest=None):
    """Side-by-side comparison of a benign/suspicious pair.

    2 rows (benign, suspicious) x N variant columns.
    """
    variants = variants or ALL_VARIANTS
    output_dir = output_dir or OUTPUT_DIR
    output_path = output_path or os.path.join(
        output_dir, "montages",
        f"pair_{app_name}_{benign_id}_vs_{suspicious_id}.png"
    )
    return create_montage(
        [benign_id, suspicious_id], variants,
        output_dir=output_dir, output_path=output_path, manifest=manifest
    )


def create_standalone_progression(output_dir=None, manifest=None):
    """Show standalone_1 through standalone_4 (RO count scaling).

    4 rows (5, 50, 500, 5000 ROs) x 8 variant columns.
    Region 0 only for compactness.
    """
    output_dir = output_dir or OUTPUT_DIR
    sample_ids = ["S16", "S18", "S20", "S22"]  # standalone 1-4, region 0
    output_path = os.path.join(output_dir, "montages",
                                "standalone_progression.png")
    return create_montage(
        sample_ids, ALL_VARIANTS,
        output_dir=output_dir, output_path=output_path, manifest=manifest
    )


def create_class_montages(manifest, output_dir=None):
    """Create one montage per class (benign, suspicious, standalone).

    Each montage shows all samples of that class × all 8 variants.

    Returns:
        list of output paths
    """
    output_dir = output_dir or OUTPUT_DIR
    paths = []

    # Group samples by class, one per app (region 0 only)
    class_groups = {
        0: {"name": "benign",     "samples": []},
        1: {"name": "suspicious", "samples": []},
        2: {"name": "standalone", "samples": []},
    }
    seen_apps = {0: set(), 1: set(), 2: set()}
    for row in manifest:
        cl = int(row["class_label"])
        app = row["base_app_id"]
        if app not in seen_apps[cl] and row["region_id"] == "0":
            class_groups[cl]["samples"].append(row["sample_id"])
            seen_apps[cl].add(app)

    for cl in sorted(class_groups):
        grp = class_groups[cl]
        name = grp["name"]
        sids = grp["samples"]
        out_path = os.path.join(output_dir, "montages",
                                f"class_{cl}_{name}.png")
        print(f"  Montage: class {cl} ({name}, {len(sids)} samples)...")
        p = create_montage(sids, ALL_VARIANTS, output_dir=output_dir,
                           output_path=out_path, manifest=manifest)
        paths.append(p)

    return paths


def create_benign_vs_standalone(manifest, case="a", output_dir=None):
    """Side-by-side benign vs standalone comparison montage.

    4 rows (one per app) x 8 columns (var1 Ben, var1 Std, var2 Ben, ...).
    Row labels include LUT counts for both benign and standalone samples.

    Args:
        manifest: loaded manifest list
        case: "a" for Case A variants (A1-A4), "b" for Case B (B1-B4)
        output_dir: base output directory

    Returns:
        path to saved montage
    """
    output_dir = output_dir or OUTPUT_DIR
    font = _get_font()

    benign = [r for r in manifest
              if r["class_label"] == "0" and r["region_id"] == "0"]
    standalone = [r for r in manifest
                  if r["class_label"] == "2" and r["region_id"] == "0"]

    variants = CASE_A_VARIANTS if case == "a" else CASE_B_VARIANTS
    case_label = case.upper()

    n_rows = len(benign)
    row_header_w = 140
    col_header_h = 20
    n_cols = len(variants) * 2
    w = row_header_w + n_cols * (CELL_SIZE + PADDING) + PADDING
    h = col_header_h + n_rows * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    # Column headers
    for vi, var in enumerate(variants):
        for ci, cls in enumerate(["Ben", "Std"]):
            x = row_header_w + PADDING + (vi * 2 + ci) * (CELL_SIZE + PADDING)
            draw.text((x + CELL_SIZE // 2 - 20, 2),
                      f"{var} {cls}", fill=0, font=font)

    # Rows
    for i in range(n_rows):
        y = col_header_h + PADDING + i * (CELL_SIZE + PADDING)
        b = benign[i]
        s = standalone[i]
        draw.text((4, y + 4), b["base_app_id"][:14], fill=0, font=font)
        draw.text((4, y + 16),
                  f"  {int(b['lut_count']):,} LUTs", fill=0, font=font)
        draw.text((4, y + 32), s["base_app_id"][:14], fill=0, font=font)
        draw.text((4, y + 44),
                  f"  {int(s['lut_count']):,} LUTs", fill=0, font=font)

        subdir = "case_a" if case == "a" else "case_b"
        for vi, var in enumerate(variants):
            # Benign cell
            bp = os.path.join(output_dir, subdir, var,
                              f'{b["sample_id"]}_{var}.png')
            if os.path.exists(bp):
                img = Image.open(bp).convert("L")
                x = row_header_w + PADDING + (vi * 2) * (CELL_SIZE + PADDING)
                canvas.paste(img, (x, y))
            # Standalone cell
            sp = os.path.join(output_dir, subdir, var,
                              f'{s["sample_id"]}_{var}.png')
            if os.path.exists(sp):
                img = Image.open(sp).convert("L")
                x = row_header_w + PADDING + (vi * 2 + 1) * (CELL_SIZE + PADDING)
                canvas.paste(img, (x, y))

    out = os.path.join(output_dir, "montages",
                       f"benign_vs_standalone_case_{case_label}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    return out


def create_benign_vs_standalone_single(manifest, variant="A2", output_dir=None):
    """Single-variant benign vs standalone comparison.

    4 rows (one per app) x 2 columns (benign, standalone).
    Row labels include LUT counts.

    Args:
        manifest: loaded manifest list
        variant: which variant to show (e.g. "A2")
        output_dir: base output directory

    Returns:
        path to saved montage
    """
    output_dir = output_dir or OUTPUT_DIR
    font = _get_font()

    benign = [r for r in manifest
              if r["class_label"] == "0" and r["region_id"] == "0"]
    standalone = [r for r in manifest
                  if r["class_label"] == "2" and r["region_id"] == "0"]

    n_rows = len(benign)
    row_header_w = 140
    col_header_h = 20
    w = row_header_w + 2 * (CELL_SIZE + PADDING) + PADDING
    h = col_header_h + n_rows * (CELL_SIZE + PADDING) + PADDING

    canvas = Image.new("L", (w, h), 240)
    draw = ImageDraw.Draw(canvas)

    for j, title in enumerate([f"{variant} Benign", f"{variant} Standalone"]):
        x = row_header_w + PADDING + j * (CELL_SIZE + PADDING)
        draw.text((x + CELL_SIZE // 2 - 30, 2), title, fill=0, font=font)

    subdir = "case_a" if variant.startswith("A") else "case_b"
    for i in range(n_rows):
        y = col_header_h + PADDING + i * (CELL_SIZE + PADDING)
        b = benign[i]
        s = standalone[i]
        draw.text((4, y + 4), b["base_app_id"][:14], fill=0, font=font)
        draw.text((4, y + 16),
                  f"  {int(b['lut_count']):,} LUTs", fill=0, font=font)
        draw.text((4, y + 32), s["base_app_id"][:14], fill=0, font=font)
        draw.text((4, y + 44),
                  f"  {int(s['lut_count']):,} LUTs", fill=0, font=font)

        bp = os.path.join(output_dir, subdir, variant,
                          f'{b["sample_id"]}_{variant}.png')
        if os.path.exists(bp):
            canvas.paste(Image.open(bp).convert("L"),
                         (row_header_w + PADDING, y))

        sp = os.path.join(output_dir, subdir, variant,
                          f'{s["sample_id"]}_{variant}.png')
        if os.path.exists(sp):
            canvas.paste(Image.open(sp).convert("L"),
                         (row_header_w + PADDING + CELL_SIZE + PADDING, y))

    out = os.path.join(output_dir, "montages",
                       f"benign_vs_standalone_{variant}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    return out


def generate_all_montages(manifest, output_dir=None):
    """Generate all planned montage sheets.

    Returns:
        list of output paths
    """
    output_dir = output_dir or OUTPUT_DIR
    paths = []

    print("  Montage: full 10x8 comparison (pilot subset)...")
    p = create_montage(
        PILOT_SUBSET, ALL_VARIANTS,
        output_dir=output_dir,
        output_path=os.path.join(output_dir, "montages",
                                  "comparison_10x8.png"),
        manifest=manifest,
    )
    paths.append(p)

    # Paired comparisons (benign vs suspicious, same app)
    pairs = [
        ("S00", "S08", "euclidean"),
        ("S02", "S10", "cosine"),
        ("S04", "S12", "vadd"),
        ("S06", "S14", "aes"),
    ]
    for ben, sus, app in pairs:
        print(f"  Montage: pair {app} ({ben} vs {sus})...")
        p = create_pair_comparison(ben, sus, app, output_dir=output_dir,
                                   manifest=manifest)
        paths.append(p)

    # Standalone progression
    print("  Montage: standalone progression (5→50→500→5000 ROs)...")
    p = create_standalone_progression(output_dir=output_dir, manifest=manifest)
    paths.append(p)

    # Per-class montages
    class_paths = create_class_montages(manifest, output_dir=output_dir)
    paths.extend(class_paths)

    # Benign vs standalone comparisons
    for case in ("a", "b"):
        print(f"  Montage: benign vs standalone (Case {case.upper()})...")
        p = create_benign_vs_standalone(manifest, case=case,
                                        output_dir=output_dir)
        paths.append(p)

    print("  Montage: benign vs standalone (A2 only)...")
    p = create_benign_vs_standalone_single(manifest, variant="A2",
                                           output_dir=output_dir)
    paths.append(p)

    return paths
