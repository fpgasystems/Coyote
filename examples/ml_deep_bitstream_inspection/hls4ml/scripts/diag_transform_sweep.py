#!/usr/bin/env python3
"""
Diagnostic: host-side byte-order transform sweep (§8.2/8.3) + frame-reset test (§8.5).

Tests 8 different input packing transforms against the currently-deployed CNN bitstream
by rearranging prepared-input bytes before DMA, requiring NO bitstream rebuild.
Also runs the §8.5 frame-reset / line-buffer state test.

Usage:
    python scripts/diag_transform_sweep.py --deploy-root PATH --sweep-only --skip-reprogram
"""

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO = Path(__file__).resolve().parent.parent
BASELINE_ROOT = (
    REPO / "artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat"
    / "BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8"
    / "hls_sweeps/rf1_hls_578358bbe266_copy/fold_0/u55c_deployment"
)
HLS_REF_CSV = (
    REPO / "artifacts/cnn_small_hls_opt_img512/notebook_pruned_qat"
    / "BASELINE_pruned_qat_w6_a6_s50_pruneend200_kfold5_db9a98479fa8"
    / "hls_sweeps/rf1_hls_578358bbe266/fold_0/parity/hls_per_sample.csv"
)

PIXELS_PER_SAMPLE = 262144  # overridden from deployment ABI when available
BEATS_PER_SAMPLE = 8192
PIXELS_PER_BEAT = 32        # 512 bits / 16 bits


# ---------------------------------------------------------------------------
# Transforms
# Each takes a (262144,) uint8 flat byte array and returns transformed bytes.
# The transforms operate on the RAW byte representation of the prepared input.
# ---------------------------------------------------------------------------

def _load_bytes(path: Path) -> np.ndarray:
    return np.frombuffer(path.read_bytes(), dtype=np.uint8).copy()


def _save_bytes(arr: np.ndarray, path: Path) -> None:
    path.write_bytes(arr.tobytes())


def infer_geometry(deploy: Path, rows: list[dict]) -> dict:
    """Infer sample/beat geometry from bitstream manifest and prepared files."""
    global PIXELS_PER_SAMPLE, BEATS_PER_SAMPLE, PIXELS_PER_BEAT

    abi = {}
    bit_manifest = deploy / "bitstream_manifest.json"
    if bit_manifest.exists():
        data = json.loads(bit_manifest.read_text())
        abi = (data.get("stage_fingerprint") or {}).get("abi") or {}

    first_path = Path(rows[0]["input_path"])
    sample_bytes = int(rows[0].get("input_bytes") or first_path.stat().st_size)
    axi_data_bits = int(abi.get("axi_data_bits") or 512)
    fixed_width = int(abi.get("fixed_width") or 16)
    beat_bytes = axi_data_bits // 8
    lane_bytes = fixed_width // 8
    if sample_bytes % beat_bytes != 0:
        raise ValueError(f"sample size {sample_bytes} is not a multiple of beat size {beat_bytes}")
    if beat_bytes % lane_bytes != 0:
        raise ValueError(f"beat size {beat_bytes} is not a multiple of lane size {lane_bytes}")

    PIXELS_PER_BEAT = int(abi.get("pixels_per_beat") or (beat_bytes // lane_bytes))
    BEATS_PER_SAMPLE = int(abi.get("beats_per_sample") or (sample_bytes // beat_bytes))
    PIXELS_PER_SAMPLE = int(abi.get("pixels_per_sample") or (sample_bytes // lane_bytes))

    expected_bytes = BEATS_PER_SAMPLE * PIXELS_PER_BEAT * lane_bytes
    if expected_bytes != sample_bytes:
        raise ValueError(
            f"inferred geometry mismatch: beats={BEATS_PER_SAMPLE} lanes={PIXELS_PER_BEAT} "
            f"lane_bytes={lane_bytes} gives {expected_bytes} bytes, sample has {sample_bytes}"
        )

    return {
        "abi": abi,
        "sample_bytes": sample_bytes,
        "beat_bytes": beat_bytes,
        "lane_bytes": lane_bytes,
        "pixels_per_beat": PIXELS_PER_BEAT,
        "beats_per_sample": BEATS_PER_SAMPLE,
        "pixels_per_sample": PIXELS_PER_SAMPLE,
    }


def t_identity(raw: np.ndarray) -> np.ndarray:
    """A: identity — no change."""
    return raw.copy()


def t_reverse_lanes(raw: np.ndarray) -> np.ndarray:
    """B: reverse the 32 × 16-bit lanes within each 512-bit beat.

    Within each 64-byte beat, swap the order of the 32 two-byte groups:
    [lane0, lane1, ..., lane31] → [lane31, ..., lane1, lane0]
    """
    # shape: (8192, 32, 2)
    beats = raw.reshape(BEATS_PER_SAMPLE, PIXELS_PER_BEAT, 2)
    return beats[:, ::-1, :].copy().reshape(-1)


def t_byteswap(raw: np.ndarray) -> np.ndarray:
    """C: byte-swap each 16-bit lane (swap bytes 0↔1 within every int16)."""
    pairs = raw.reshape(-1, 2)
    return pairs[:, ::-1].copy().reshape(-1)


def t_lanes_then_byteswap(raw: np.ndarray) -> np.ndarray:
    """D: reverse lanes then byte-swap each lane (B followed by C)."""
    return t_byteswap(t_reverse_lanes(raw))


def _bit_reverse_uint16_bytes(arr: np.ndarray) -> np.ndarray:
    """Reverse all 16 bits of each 16-bit value, operating on raw bytes."""
    u16 = arr.view(np.uint16).copy()
    u16 = ((u16 & 0xFF00) >> 8) | ((u16 & 0x00FF) << 8)
    u16 = ((u16 & 0xF0F0) >> 4) | ((u16 & 0x0F0F) << 4)
    u16 = ((u16 & 0xCCCC) >> 2) | ((u16 & 0x3333) << 2)
    u16 = ((u16 & 0xAAAA) >> 1) | ((u16 & 0x5555) << 1)
    return u16.view(np.uint8)


def t_full_512bit_bitreversal(raw: np.ndarray) -> np.ndarray:
    """E: full 512-bit bit reversal (AMD-OHC-2024 style).

    Reverses lane order within each beat AND bit-reverses each 16-bit lane
    value, equivalent to reversing all 512 bits of each TDATA word.
    """
    reversed_lanes = t_reverse_lanes(raw)
    return _bit_reverse_uint16_bytes(reversed_lanes)


def t_reverse_64bit_subwords(raw: np.ndarray) -> np.ndarray:
    """F: reverse the 8 × 64-bit subwords within each 512-bit beat.

    Treats each beat as 8 groups of 8 bytes and reverses their order:
    [g0, g1, g2, g3, g4, g5, g6, g7] → [g7, g6, g5, g4, g3, g2, g1, g0]
    """
    # shape: (8192, 8, 8)
    beats = raw.reshape(BEATS_PER_SAMPLE, 8, 8)
    return beats[:, ::-1, :].copy().reshape(-1)


def t_reverse_128bit_subwords(raw: np.ndarray) -> np.ndarray:
    """G: reverse the 4 × 128-bit subwords within each 512-bit beat.

    Treats each beat as 4 groups of 16 bytes and reverses their order.
    """
    # shape: (8192, 4, 16)
    beats = raw.reshape(BEATS_PER_SAMPLE, 4, 16)
    return beats[:, ::-1, :].copy().reshape(-1)


def t_bitreverse_each_lane(raw: np.ndarray) -> np.ndarray:
    """H: bit-reverse each 16-bit lane (no lane reordering)."""
    return _bit_reverse_uint16_bytes(raw.copy())


TRANSFORMS = {
    "A_identity": t_identity,
    "B_reverse_lanes": t_reverse_lanes,
    "C_byteswap": t_byteswap,
    "D_lanes_byteswap": t_lanes_then_byteswap,
    "E_full_bitreversal": t_full_512bit_bitreversal,
    "F_rev_64b_subwords": t_reverse_64bit_subwords,
    "G_rev_128b_subwords": t_reverse_128bit_subwords,
    "H_bitrev_each_lane": t_bitreverse_each_lane,
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_hls_ref(csv_path: Path) -> dict:
    """Return {sample_index: logit} from hls_per_sample.csv."""
    ref = {}
    with open(csv_path) as f:
        for row in csv.DictReader(f):
            ref[int(row["sample_index"])] = float(row["logit"])
    return ref


def read_manifest(path: Path) -> list[dict]:
    with open(path) as f:
        return list(csv.DictReader(f))


def write_manifest(rows: list[dict], path: Path) -> None:
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)


def run_host(
    host_bin: Path,
    manifest_path: Path,
    output_path: Path,
    shell_bin: Path | None = None,
    max_samples: int = -1,
) -> bool:
    cmd = [
        str(host_bin),
        "--manifest", str(manifest_path),
        "--output", str(output_path),
    ]
    if shell_bin:
        cmd += ["--reconfigure-shell", str(shell_bin)]
    if max_samples > 0:
        cmd += ["--max-samples", str(max_samples)]
    print(f"  $ {' '.join(cmd)}")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.stdout:
        print(r.stdout.rstrip())
    if r.stderr:
        print(r.stderr.rstrip(), file=sys.stderr)
    return r.returncode == 0


def _corr(a: list[float], b: list[float]) -> float:
    if len(a) <= 1:
        return float("nan")
    return float(np.corrcoef(np.array(a), np.array(b))[0, 1])


def stats(hw: list[float], hls: list[float], run_order: list[int] | None = None) -> dict:
    hw_a = np.array(hw)
    hls_a = np.array(hls)
    diff = hw_a - hls_a
    order = list(range(len(hw))) if run_order is None else run_order
    return {
        "n": len(hw_a),
        "mean_diff": float(diff.mean()),
        "min_diff": float(diff.min()),
        "max_diff": float(diff.max()),
        "mae": float(np.abs(diff).mean()),
        "pearson_corr": _corr(hw, hls),
        "hw_vs_run_order_corr": _corr(hw, order),
        "hls_vs_run_order_corr": _corr(hls, order),
        "hw_mean": float(hw_a.mean()),
        "hls_mean": float(hls_a.mean()),
    }


def parse_hw_csv(path: Path) -> dict[int, float]:
    result = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            result[int(row["sample_index"])] = float(row["logit"])
    return result


def parse_hw_csv_rows(path: Path) -> list[dict]:
    rows = []
    with open(path) as f:
        for row in csv.DictReader(f):
            rows.append(row)
    return rows


# ---------------------------------------------------------------------------
# Frame-reset test (§8.5)
# ---------------------------------------------------------------------------

def run_framereset_test(deploy: Path, out_dir: Path) -> None:
    host_bin = deploy / "coyote_sw/build/coyote_qkeras_host"
    shell_bin = deploy / "coyote_hw/build_u55c/bitstreams/shell_top.bin"
    prepared = deploy / "prepared_inputs"
    manifest_src = read_manifest(prepared / "manifest.csv")
    # Keep only sample 0
    s0 = [r for r in manifest_src if int(r["sample_index"]) == 0]
    if not s0:
        print("ERROR: sample 0 not found in manifest")
        return

    print("\n=== §8.5 Frame-reset / line-buffer state test ===")
    print(f"Reprogramming FPGA with CNN bitstream: {shell_bin}")
    freset_out = out_dir / "framereset"
    freset_out.mkdir(parents=True, exist_ok=True)
    manifest_path = freset_out / "manifest_sample0.csv"
    write_manifest(s0, manifest_path)

    # Run 1: first run immediately after reprogramming (no idle wait)
    out1 = freset_out / "run_immediate_after_reconfig.csv"
    print("Run 1: immediately after reprogramming (no idle wait) ...")
    ok = run_host(host_bin, manifest_path, out1, shell_bin=shell_bin, max_samples=1)
    r1 = parse_hw_csv(out1) if ok and out1.exists() else {}
    logit1 = r1.get(0, float("nan"))
    print(f"  result: sample_0 logit = {logit1}")

    # Wait 15 seconds
    print("Waiting 15 seconds (idle, no frames sent) ...")
    time.sleep(15)

    # Run 2: first run after idle wait
    out2 = freset_out / "run_after_15s_idle.csv"
    print("Run 2: first run after 15s idle ...")
    ok = run_host(host_bin, manifest_path, out2, max_samples=1)
    r2 = parse_hw_csv(out2) if ok and out2.exists() else {}
    logit2 = r2.get(0, float("nan"))
    print(f"  result: sample_0 logit = {logit2}")

    # Runs 3-7: rapid repeated runs
    repeated_logits = []
    for i in range(5):
        out_r = freset_out / f"run_repeat_{i+1}.csv"
        ok = run_host(host_bin, manifest_path, out_r, max_samples=1)
        r = parse_hw_csv(out_r) if ok and out_r.exists() else {}
        lgt = r.get(0, float("nan"))
        repeated_logits.append(lgt)
        print(f"  run_repeat_{i+1}: sample_0 logit = {lgt}")

    print("\nFrame-reset summary:")
    print(f"  HLS reference sample_0:  -0.5625")
    print(f"  run_1 (immediate):        {logit1:.6f}")
    print(f"  run_2 (after 15s idle):   {logit2:.6f}")
    print(f"  repeated runs:            {repeated_logits}")
    all_same = all(abs(v - logit1) < 1e-6 for v in [logit2] + repeated_logits)
    verdict = "H3 RULED OUT (all runs identical)" if all_same else "H3 POSSIBLE (first run differs)"
    print(f"  Verdict: {verdict}")

    summary_path = freset_out / "summary.txt"
    with open(summary_path, "w") as f:
        f.write(f"HLS reference sample_0: -0.5625\n")
        f.write(f"run_1 immediate:         {logit1:.6f}\n")
        f.write(f"run_2 after_15s_idle:    {logit2:.6f}\n")
        f.write(f"repeated_runs:           {repeated_logits}\n")
        f.write(f"Verdict: {verdict}\n")
    print(f"  Written: {summary_path}")


# ---------------------------------------------------------------------------
# Transform sweep (§8.2/8.3)
# ---------------------------------------------------------------------------

def run_transform_sweep(
    deploy: Path,
    out_dir: Path,
    hls_ref: dict,
    max_samples: int = -1,
    randomize_sample_order: bool = False,
    random_seed: int = 1,
) -> None:
    host_bin = deploy / "coyote_sw/build/coyote_qkeras_host"
    prepared = deploy / "prepared_inputs"
    manifest_src = read_manifest(prepared / "manifest.csv")
    if max_samples > 0:
        manifest_src = manifest_src[:max_samples]
    if randomize_sample_order:
        rng = np.random.default_rng(random_seed)
        order = rng.permutation(len(manifest_src)).tolist()
        manifest_src = [manifest_src[i] for i in order]
    geometry = infer_geometry(deploy, manifest_src)

    # Load all prepared inputs as raw bytes
    print(f"\nLoading {len(manifest_src)} prepared inputs ...")
    print(
        "Geometry: "
        f"sample_bytes={geometry['sample_bytes']} "
        f"beats_per_sample={geometry['beats_per_sample']} "
        f"pixels_per_beat={geometry['pixels_per_beat']} "
        f"pixels_per_sample={geometry['pixels_per_sample']}"
    )
    sample_bytes: dict[int, np.ndarray] = {}
    for row in manifest_src:
        idx = int(row["sample_index"])
        src_path = Path(row["input_path"])
        sample_bytes[idx] = _load_bytes(src_path)

    sweep_dir = out_dir / "transform_sweep"
    sweep_dir.mkdir(parents=True, exist_ok=True)
    order_path = sweep_dir / "sample_execution_order.csv"
    with open(order_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["run_order", "sample_index", "sample_id", "hls_logit"])
        writer.writeheader()
        for run_order, row in enumerate(manifest_src):
            idx = int(row["sample_index"])
            writer.writerow({
                "run_order": run_order,
                "sample_index": idx,
                "sample_id": row.get("sample_id", ""),
                "hls_logit": hls_ref.get(idx, ""),
            })

    all_stats = []
    per_sample_all = {}  # transform_name → {sample_index: logit}

    print("\n=== §8.2/8.3 Host-side transform sweep ===")
    print(f"Transforms to test: {list(TRANSFORMS.keys())}\n")
    if randomize_sample_order:
        print(f"Sample execution order: randomized with seed {random_seed}")
    else:
        print("Sample execution order: manifest order")
    print(f"Execution order written: {order_path}\n")

    for tname, tfunc in TRANSFORMS.items():
        print(f"--- Transform: {tname} ---")
        t_dir = sweep_dir / tname
        t_dir.mkdir(parents=True, exist_ok=True)

        # Generate transformed input files and manifest
        new_rows = []
        for row in manifest_src:
            idx = int(row["sample_index"])
            raw = sample_bytes[idx]
            transformed = tfunc(raw)
            out_path = t_dir / f"sample_{idx:04d}.bin"
            _save_bytes(transformed, out_path)
            new_row = dict(row)
            new_row["input_path"] = str(out_path)
            new_rows.append(new_row)

        manifest_path = t_dir / "manifest.csv"
        write_manifest(new_rows, manifest_path)

        # Run host binary
        hw_csv = t_dir / "hardware_results.csv"
        ok = run_host(host_bin, manifest_path, hw_csv)
        if not ok or not hw_csv.exists():
            print(f"  ERROR: host binary failed for {tname}")
            continue

        hw_rows = parse_hw_csv_rows(hw_csv)
        hw = {int(row["sample_index"]): float(row["logit"]) for row in hw_rows}
        # Pair with HLS reference
        hw_vals, hls_vals, run_orders = [], [], []
        for run_order, row in enumerate(hw_rows):
            idx = int(row["sample_index"])
            if idx in hls_ref:
                hw_vals.append(float(row["logit"]))
                hls_vals.append(hls_ref[idx])
                run_orders.append(run_order)

        if not hw_vals:
            print(f"  ERROR: no matching HLS reference rows")
            continue

        s = stats(hw_vals, hls_vals, run_orders)
        s["transform"] = tname
        all_stats.append(s)
        per_sample_all[tname] = hw

        print(f"  n={s['n']}  mean(hw-hls)={s['mean_diff']:+.4f}  "
              f"range=[{s['min_diff']:+.4f}, {s['max_diff']:+.4f}]  "
              f"mae={s['mae']:.4f}  corr={s['pearson_corr']:.4f}  "
              f"hw_vs_order={s['hw_vs_run_order_corr']:.4f}")

    # Write summary CSV
    if all_stats:
        summary_path = sweep_dir / "summary.csv"
        fieldnames = ["transform", "n", "mean_diff", "min_diff", "max_diff", "mae",
                      "pearson_corr", "hw_vs_run_order_corr", "hls_vs_run_order_corr",
                      "hw_mean", "hls_mean"]
        with open(summary_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(all_stats)
        print(f"\nSummary written: {summary_path}")

        # Print ranked table
        ranked = sorted(all_stats, key=lambda r: abs(r["mean_diff"]))
        print("\n=== Transform sweep ranking (by |mean(hw-hls)|, ascending = better) ===")
        print(f"{'Transform':<22} {'mean_diff':>10} {'mae':>8} {'corr':>8} {'hw/order':>9}")
        print("-" * 62)
        for s in ranked:
            flag = " *** BEST ***" if s == ranked[0] else ""
            print(
                f"{s['transform']:<22} {s['mean_diff']:>+10.4f} {s['mae']:>8.4f} "
                f"{s['pearson_corr']:>8.4f} {s['hw_vs_run_order_corr']:>9.4f}{flag}"
            )

        best = ranked[0]
        print(f"\nLeading candidate: {best['transform']}")
        print(f"  mean(hw-hls)={best['mean_diff']:+.6f}, mae={best['mae']:.6f}, corr={best['pearson_corr']:.6f}")
        if abs(best["mean_diff"]) < 0.1 and best["mae"] < 0.2:
            print("  => This transform appears to fix the mismatch!")
        elif abs(best["mean_diff"]) < 0.5:
            print("  => This transform significantly reduces bias but may need further investigation.")
        else:
            print("  => No transform fully resolves the mismatch. Consider bitstream-level diagnostics (§8.1).")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deploy-root", type=Path, default=BASELINE_ROOT)
    parser.add_argument(
        "--hls-ref-csv",
        type=Path,
        default=None,
        help="Reference HLS per-sample CSV. Defaults to <deploy-root>/../parity/hls_per_sample.csv.",
    )
    parser.add_argument("--out-dir", type=Path, default=None)
    parser.add_argument("--max-samples", type=int, default=-1)
    parser.add_argument("--randomize-sample-order", action="store_true",
                        help="Shuffle manifest rows before each transform run while preserving sample_index labels.")
    parser.add_argument("--random-seed", type=int, default=1)
    parser.add_argument("--framereset-only", action="store_true")
    parser.add_argument("--sweep-only", action="store_true")
    parser.add_argument("--skip-reprogram", action="store_true",
                        help="Skip the initial reprogram step (FPGA assumed already loaded)")
    args = parser.parse_args()

    deploy = args.deploy_root
    out_dir = args.out_dir or (deploy / "diagnostics")

    if not deploy.exists():
        print(f"ERROR: deploy root not found: {deploy}")
        sys.exit(1)

    hls_ref_csv = args.hls_ref_csv or (deploy.parent / "parity" / "hls_per_sample.csv")
    if not hls_ref_csv.exists():
        hls_ref_csv = HLS_REF_CSV
    hls_ref = load_hls_ref(hls_ref_csv)
    print(f"Loaded {len(hls_ref)} HLS reference logits from {hls_ref_csv}")

    run_freset = not args.sweep_only
    run_sweep = not args.framereset_only

    host_bin = deploy / "coyote_sw/build/coyote_qkeras_host"
    shell_bin = deploy / "coyote_hw/build_u55c/bitstreams/shell_top.bin"

    if not args.skip_reprogram and not args.framereset_only:
        # Reprogram upfront for the sweep (framereset will also reprogram itself)
        print(f"\nReprogramming FPGA with CNN shell: {shell_bin}")
        prepared = deploy / "prepared_inputs"
        manifest_src = read_manifest(prepared / "manifest.csv")
        s0 = [r for r in manifest_src if int(r["sample_index"]) == 0]
        if s0:
            tmp_out = out_dir / "transform_sweep/reprogram_check.csv"
            tmp_out.parent.mkdir(parents=True, exist_ok=True)
            tmp_manifest = out_dir / "transform_sweep/manifest_s0.csv"
            write_manifest(s0, tmp_manifest)
            run_host(host_bin, tmp_manifest, tmp_out, shell_bin=shell_bin, max_samples=1)

    if run_freset:
        run_framereset_test(deploy, out_dir)

    if run_sweep:
        run_transform_sweep(
            deploy,
            out_dir,
            hls_ref,
            max_samples=args.max_samples,
            randomize_sample_order=args.randomize_sample_order,
            random_seed=args.random_seed,
        )

    print("\nDone.")


if __name__ == "__main__":
    main()
