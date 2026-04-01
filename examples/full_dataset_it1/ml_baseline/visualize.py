"""Debug visualization: save sample images from the training set.

Outputs a grid of bitstream images so you can visually verify what the model sees.
Also saves individual sample images with metadata labels.
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from dataset import load_manifest, bitstream_to_image, BITSTREAM_DIR, IMG_SIZE

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "debug_viz")


def get_font(size=14):
    try:
        return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", size)
    except (IOError, OSError):
        return ImageFont.load_default()


def save_sample_grid(samples, filename="sample_grid.png", n_per_class=5):
    """Save a grid with n_per_class benign samples (top) and n_per_class standalone (bottom)."""
    benign = [s for s in samples if int(s["class_label"]) == 0][:n_per_class]
    standalone = [s for s in samples if int(s["class_label"]) == 1][:n_per_class]

    cell = 256  # display size per cell
    label_h = 30
    cols = n_per_class
    rows = 2
    width = cols * cell
    height = rows * (cell + label_h) + label_h  # extra top label

    grid = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(grid)
    font = get_font(12)

    # Row titles
    draw.text((4, 4), "BENIGN", fill=255, font=font)
    draw.text((4, cell + label_h + 4), "STANDALONE (RO>=4000)", fill=255, font=font)

    for row_idx, row_samples in enumerate([benign, standalone]):
        y_off = label_h + row_idx * (cell + label_h)
        for col_idx, s in enumerate(row_samples):
            bin_path = os.path.join(BITSTREAM_DIR, s["bitstream_path"])
            img = bitstream_to_image(bin_path, IMG_SIZE)
            # Resize for grid display
            pil_img = Image.fromarray(img, mode="L").resize((cell, cell), Image.BILINEAR)
            grid.paste(pil_img, (col_idx * cell, y_off))

            # Label underneath
            label = f"{s['sample_id']} {s['app_name']} ro={s['ro_count']}"
            draw.text(
                (col_idx * cell + 4, y_off + cell + 2),
                label[:30],
                fill=200,
                font=get_font(10),
            )

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    out_path = os.path.join(OUTPUT_DIR, filename)
    grid.save(out_path)
    print(f"Saved grid: {out_path}")


def save_individual_samples(samples, n=4):
    """Save a few full-resolution individual images for close inspection."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for s in samples[:n]:
        bin_path = os.path.join(BITSTREAM_DIR, s["bitstream_path"])
        img = bitstream_to_image(bin_path, IMG_SIZE)
        pil_img = Image.fromarray(img, mode="L")
        fname = f"{s['sample_id']}_{s['class_name']}_{s['app_name']}_ro{s['ro_count']}.png"
        out_path = os.path.join(OUTPUT_DIR, fname)
        pil_img.save(out_path)
        print(f"Saved: {out_path}")


def main():
    samples = load_manifest()
    print(f"Loaded {len(samples)} samples "
          f"({sum(1 for s in samples if int(s['class_label'])==0)} benign, "
          f"{sum(1 for s in samples if int(s['class_label'])==1)} standalone)")

    save_sample_grid(samples, n_per_class=5)

    # Save a few full-res individuals from each class
    benign = [s for s in samples if int(s["class_label"]) == 0]
    standalone = [s for s in samples if int(s["class_label"]) == 1]
    save_individual_samples(benign, n=10)
    save_individual_samples(standalone, n=10)


if __name__ == "__main__":
    main()
