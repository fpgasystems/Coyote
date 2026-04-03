"""Debug visualization: save sample images from the training set.

Outputs a grid of bitstream images so you can visually verify what the model sees.
Also saves individual sample images with metadata labels.
Provides helpers for hardest-sample dumps and augmentation sanity checks.
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


def save_hardest_samples(hardest_rows, run_dir, top_n=10):
    """Save annotated full-resolution PNGs for the hardest samples.

    Args:
        hardest_rows: list of dicts from write_hardest_csv (sorted by loss desc),
                      each with sample_id, class_name, app_name, probability,
        per_sample_bce_loss, bitstream_path, etc.
        run_dir: directory to save images into.
        top_n: how many to save.
    """
    out_dir = os.path.join(run_dir, "hardest_images")
    os.makedirs(out_dir, exist_ok=True)

    cell = IMG_SIZE
    label_h = 60
    font = get_font(12)
    font_small = get_font(10)

    for rank, row in enumerate(hardest_rows[:top_n]):
        bin_path = os.path.join(BITSTREAM_DIR, row["bitstream_path"])
        if not os.path.isfile(bin_path):
            continue

        sid = row.get("sample_id", "?")
        cls = row.get("class_name", f"class{row.get('class_label', '?')}")
        app = row.get("app_name", "?")
        prob = float(row.get("probability", 0))
        loss_val = float(row.get("per_sample_bce_loss", 0))
        pred = int(row.get("predicted_label", 0))
        correct = row.get("correct", False)
        ro = row.get("ro_count", "?")

        line1 = f"{sid} | {cls} | {app} | ro={ro}"
        line2 = f"p={prob:.4f} pred={pred} loss={loss_val:.4f} {'OK' if correct else 'WRONG'}"

        correct_str = "ok" if correct else "wrong"
        fname = f"rank{rank:02d}_{sid}_{cls}_p{prob:.3f}_loss{loss_val:.3f}_{correct_str}.png"
        img = bitstream_to_image(bin_path, IMG_SIZE)
        pil_img = Image.fromarray(img, mode="L").resize((cell, cell), Image.BILINEAR)

        # Create annotated image with label area.
        canvas = Image.new("L", (cell, cell + label_h), 0)
        canvas.paste(pil_img, (0, 0))
        draw = ImageDraw.Draw(canvas)
        draw.text((4, cell + 2), line1[:120], fill=220, font=font_small)
        draw.text((4, cell + 16), line2, fill=200, font=font_small)
        canvas.save(os.path.join(out_dir, fname))

    saved_n = min(top_n, len(hardest_rows))
    print(f"Saved {saved_n} hardest-sample images to: {out_dir}")


def save_augmentation_grid(train_dataset, run_dir, n_samples=4, n_augments=4):
    """Save preview and full-resolution grids of training augmentations.

    Rows: different samples. Col 0: original (no transform). Cols 1..n_augments: augmented.
    """
    import torch

    cols = 1 + n_augments
    label_h = 20

    transform = train_dataset.transform
    font = get_font(10)

    raw_rows = []
    for row_idx in range(min(n_samples, len(train_dataset))):
        meta = train_dataset.get_metadata(row_idx)
        bin_path = os.path.join(train_dataset.bitstream_dir, meta["bitstream_path"])
        raw_img = bitstream_to_image(bin_path, train_dataset.img_size)
        raw_tensor = torch.from_numpy(raw_img.astype(np.float32) / 255.0).unsqueeze(0)

        row_images = [Image.fromarray(raw_img, mode="L")]
        for _ in range(n_augments):
            if transform is not None:
                aug_tensor = transform(raw_tensor)
            else:
                aug_tensor = raw_tensor
            aug_np = (aug_tensor.squeeze(0).numpy() * 255).astype(np.uint8)
            row_images.append(Image.fromarray(aug_np, mode="L"))

        raw_rows.append({
            "label_text": f"{meta.get('sample_id', '')} {meta.get('class_name', '')} ro={meta.get('ro_count', '')}",
            "images": row_images,
        })

    for filename, cell in [
        ("augmentation_sanity_check.png", 256),
        ("augmentation_sanity_check_fullres.png", train_dataset.img_size),
    ]:
        width = cols * cell
        height = len(raw_rows) * (cell + label_h) + label_h
        grid = Image.new("L", (width, height), 0)
        draw = ImageDraw.Draw(grid)

        draw.text((4, 2), "Original", fill=255, font=font)
        for c in range(n_augments):
            draw.text((cell * (c + 1) + 4, 2), f"Aug {c+1}", fill=255, font=font)

        for row_idx, row in enumerate(raw_rows):
            y_off = label_h + row_idx * (cell + label_h)
            for col_idx, base_img in enumerate(row["images"]):
                pil_img = base_img.resize((cell, cell), Image.BILINEAR)
                grid.paste(pil_img, (col_idx * cell, y_off))
            draw.text((4, y_off + cell + 2), row["label_text"][:35], fill=200, font=font)

        out_path = os.path.join(run_dir, filename)
        grid.save(out_path)
        print(f"Saved augmentation sanity check: {out_path}")


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
