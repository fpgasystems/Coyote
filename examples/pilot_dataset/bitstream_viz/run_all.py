#!/usr/bin/env python3
"""Generate all bitstream visualization images for the pilot dataset.

Usage:
    python3 run_all.py                    # all 24 samples, all 8 variants + montages
    python3 run_all.py --pilot            # pilot subset only (10 samples)
    python3 run_all.py --variants B1 B4   # specific variants only
    python3 run_all.py --no-montage       # skip montage generation
    python3 run_all.py --case-b-only      # Case B only
    python3 run_all.py --case-a-only      # Case A only
"""

import argparse
import os
import sys
import time

from config import (
    MANIFEST_PATH, OUTPUT_DIR, PILOT_SUBSET,
    CASE_B_VARIANTS, CASE_A_VARIANTS, ALL_VARIANTS,
)
from io_utils import load_manifest
from case_b import generate_all_case_b
from case_a import generate_all_case_a
from montage import generate_all_montages


def main():
    parser = argparse.ArgumentParser(
        description="Bitstream-to-image visualization pipeline"
    )
    parser.add_argument("--pilot", action="store_true",
                        help="Process pilot subset only (10 samples)")
    parser.add_argument("--variants", nargs="+", default=None,
                        help="Specific variants to generate (e.g., B1 A4)")
    parser.add_argument("--case-b-only", action="store_true",
                        help="Generate Case B variants only")
    parser.add_argument("--case-a-only", action="store_true",
                        help="Generate Case A variants only")
    parser.add_argument("--no-montage", action="store_true",
                        help="Skip montage generation")
    parser.add_argument("--output-dir", default=OUTPUT_DIR,
                        help="Output directory")
    parser.add_argument("--manifest", default=MANIFEST_PATH,
                        help="Path to manifest CSV")
    args = parser.parse_args()

    # Determine which variants to run
    if args.variants:
        variants = args.variants
    elif args.case_b_only:
        variants = CASE_B_VARIANTS
    elif args.case_a_only:
        variants = CASE_A_VARIANTS
    else:
        variants = ALL_VARIANTS

    b_variants = [v for v in variants if v in CASE_B_VARIANTS]
    a_variants = [v for v in variants if v in CASE_A_VARIANTS]

    sample_ids = PILOT_SUBSET if args.pilot else None

    # Load manifest
    manifest = load_manifest(args.manifest)
    n_samples = len(PILOT_SUBSET) if args.pilot else len(manifest)
    n_variants = len(variants)
    print(f"Pipeline: {n_samples} samples x {n_variants} variants = "
          f"{n_samples * n_variants} images")
    print(f"Output: {args.output_dir}")
    print()

    t0 = time.time()
    all_meta = []

    # Case B
    if b_variants:
        print(f"=== Case B ({', '.join(b_variants)}) ===")
        meta = generate_all_case_b(manifest, args.output_dir,
                                   sample_ids=sample_ids)
        all_meta.extend(meta)
        print()

    # Case A
    if a_variants:
        print(f"=== Case A ({', '.join(a_variants)}) ===")
        meta = generate_all_case_a(manifest, args.output_dir,
                                   sample_ids=sample_ids,
                                   variants=a_variants)
        all_meta.extend(meta)
        print()

    # Montages
    if not args.no_montage:
        print("=== Montages ===")
        paths = generate_all_montages(manifest, args.output_dir)
        print()

    elapsed = time.time() - t0
    print(f"Done: {len(all_meta)} images in {elapsed:.1f}s")

    # Count output files
    n_png = 0
    n_json = 0
    for root, dirs, files in os.walk(args.output_dir):
        for f in files:
            if f.endswith(".png"):
                n_png += 1
            elif f.endswith(".json"):
                n_json += 1
    print(f"Output directory: {n_png} PNGs, {n_json} JSON metadata files")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    main()
