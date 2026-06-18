#!/usr/bin/env python3
from __future__ import annotations
import argparse, csv, json, sys
from pathlib import Path
import numpy as np

ML_ROOT = Path("/pub/scratch/sdeheredia/Coyote/examples/ml_baseline")
sys.path.insert(0, str(ML_ROOT / "hls4ml"))
sys.path.insert(0, str(ML_ROOT))
from pipeline.coyote_accelerator.raw_overlay import RawCoyoteOverlay

def read_csv(path):
    with open(path, newline="") as handle:
        return list(csv.DictReader(handle))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", required=True, type=Path)
    ap.add_argument("--project-name", required=True)
    ap.add_argument("--program", default="1")
    args = ap.parse_args()
    pkg = args.package.resolve()
    runtime_project = pkg / "non_vcs_artifacts/runtime_project"
    rows = read_csv(pkg / "non_vcs_artifacts/prepared_inputs/manifest.csv")
    labels = np.load(pkg / "non_vcs_artifacts/prepared_inputs/labels.npy").astype(np.int32)
    overlay = RawCoyoteOverlay(runtime_project, project_name=args.project_name)
    if args.program == "1":
        overlay.program_hacc_fpga()
    raw = [np.fromfile(row["raw_input_path"], dtype=np.uint8) for row in rows]
    batch_size = int(json.loads((pkg / "results/performance_summary.json").read_text())["actual_observed"]["batch_size"])
    pad = (-len(raw)) % batch_size
    if pad:
        raw.extend([raw[-1]] * pad)
    pred = overlay.predict_raw(raw, (1,), batch_size).reshape(-1)[:len(rows)]
    out = pkg / "replay/fpga_validation"
    out.mkdir(parents=True, exist_ok=True)
    with (out / "predictions.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["sample_index", "label", "logit", "predicted_label", "correct"])
        for idx, (label, logit) in enumerate(zip(labels, pred)):
            plabel = int(float(logit) >= 0.0)
            writer.writerow([idx, int(label), float(logit), plabel, plabel == int(label)])
    acc = float(np.mean((pred >= 0.0).astype(np.int32) == labels))
    (out / "replay_summary.json").write_text(json.dumps({"n": len(labels), "accuracy": acc}, indent=2) + "\n")
    print(json.dumps({"n": len(labels), "accuracy": acc}, indent=2))

if __name__ == "__main__":
    main()
