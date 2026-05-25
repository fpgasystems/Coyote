"""Raw-bitstream preparation helpers for the CoyoteAccelerator path."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Sequence

import numpy as np

from ..part1_common import FlowContext, file_sha256, write_csv, write_json


def bitstream_to_sequence(raw: np.ndarray, sequence_length: int, invert: bool = True) -> np.ndarray:
    data = np.asarray(raw, dtype=np.uint8).reshape(-1)
    if len(data) <= sequence_length:
        window = np.zeros(sequence_length, dtype=np.uint8)
        window[: len(data)] = data
    else:
        indices = np.linspace(0, len(data) - 1, sequence_length, dtype=np.int64)
        window = data[indices]
    return 255 - window if invert else window


def sequence_to_nhwc(sequence: np.ndarray, img_size: int) -> np.ndarray:
    seq = np.asarray(sequence, dtype=np.uint8)
    return (seq.reshape(img_size, img_size).astype(np.float32) / 255.0)[..., np.newaxis]


def raw_path_for_sample(row: dict[str, Any]) -> Path:
    if row.get("raw_input_path"):
        return Path(row["raw_input_path"])
    return Path(row["_bitstream_dir"]) / row["bitstream_path"]


def load_raw_arrays(samples: Sequence[dict[str, Any]]) -> list[np.ndarray]:
    arrays: list[np.ndarray] = []
    for sample in samples:
        path = raw_path_for_sample(sample)
        if not path.exists():
            raise FileNotFoundError(path)
        arrays.append(np.fromfile(path, dtype=np.uint8))
    return arrays


def raw_reference_nhwc(ctx: FlowContext, raw_arrays: Sequence[np.ndarray]) -> np.ndarray:
    img_size = int(ctx.config["candidate"]["img_size"])
    n_pixels = img_size * img_size
    xs = [sequence_to_nhwc(bitstream_to_sequence(raw, n_pixels), img_size) for raw in raw_arrays]
    return np.stack(xs).astype(np.float32)


def write_coyote_prepared_inputs(ctx: FlowContext, val_samples: Sequence[dict[str, Any]], force: bool = False) -> dict[str, Any]:
    """Write reference arrays and raw-input manifests for the Coyote path.

    The FPGA input remains the original raw bitstream. The saved NHWC arrays are
    used for CPU/Keras reference prediction and for checking raw downsampling
    parity.
    """

    img_size = int(ctx.config["candidate"]["img_size"])
    n_pixels = img_size * img_size
    out_dir = ctx.prepared_inputs_dir
    manifest_path = out_dir / "manifest.json"
    rows: list[dict[str, Any]] = []
    raw_arrays: list[np.ndarray] = []
    labels: list[int] = []
    for idx, row in enumerate(val_samples):
        raw_path = raw_path_for_sample(row)
        if not raw_path.exists():
            raise FileNotFoundError(raw_path)
        raw = np.fromfile(raw_path, dtype=np.uint8)
        raw_arrays.append(raw)
        label = int(row["class_label"])
        labels.append(label)
        rows.append(
            {
                "sample_index": idx,
                "sample_id": row.get("sample_id", ""),
                "class_label": label,
                "class_name": row.get("class_name", "standalone" if label else "benign"),
                "app_name": row.get("app_name", ""),
                "ro_count": row.get("ro_count", ""),
                "bitstream_path": row.get("bitstream_path", ""),
                "raw_input_path": str(raw_path),
                "raw_input_sha256": file_sha256(raw_path),
                "raw_input_bytes": raw_path.stat().st_size,
            }
        )

    fingerprint = {
        "training_fingerprint": ctx.training_fingerprint,
        "hls_fingerprint": ctx.hls_fingerprint,
        "model_slot": ctx.model_slot,
        "sample_ids": [row["sample_id"] for row in rows],
        "raw_input_sha256": [row["raw_input_sha256"] for row in rows],
        "raw_input_mode": True,
        "img_size": img_size,
        "pixels_per_sample": n_pixels,
    }
    if not force and manifest_path.exists():
        try:
            old = json.loads(manifest_path.read_text())
            if old.get("fingerprint") == fingerprint:
                print(f"prepared raw-input cache hit: {out_dir}")
                return old
        except Exception:
            pass

    out_dir.mkdir(parents=True, exist_ok=True)
    x = raw_reference_nhwc(ctx, raw_arrays)
    np.save(out_dir / "x_norm.npy", x)
    np.save(out_dir / "labels.npy", np.asarray(labels, dtype=np.int32))
    write_csv(out_dir / "manifest.csv", rows)
    manifest = {
        "fingerprint": fingerprint,
        "csv_manifest": str(out_dir / "manifest.csv"),
        "n_samples": len(rows),
        "raw_input_mode": True,
        "raw_input_abi": "64-byte header beat with little-endian uint64 raw_len, followed by raw bytes",
        "reference_x": str(out_dir / "x_norm.npy"),
        "labels": str(out_dir / "labels.npy"),
    }
    write_json(manifest_path, manifest)
    return manifest
