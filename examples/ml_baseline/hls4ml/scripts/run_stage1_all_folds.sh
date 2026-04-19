#!/usr/bin/env bash
# Run Stage 1 (ONNX export, QONNX cleanup, PyTorch hls4ml project, calibration export)
# for all folds of the default candidate.
#
# Usage: bash scripts/run_stage1_all_folds.sh [fold ...]
#   Default: folds 0 1 2 3 4
set -euo pipefail

HLS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HLS_ROOT"

PY="../../ml_baseline/.venv_hls4ml/bin/python"
mkdir -p logs

FOLDS=("$@")
if [[ ${#FOLDS[@]} -eq 0 ]]; then
    FOLDS=(0 1 2 3 4)
fi

run() {
    local fold="$1" step="$2"
    shift 2
    local log="logs/stage1_fold${fold}_${step}.log"
    echo "[fold ${fold}] ${step} -> ${log}"
    if "$PY" "$@" >"$log" 2>&1; then
        echo "[fold ${fold}] ${step} OK"
    else
        echo "[fold ${fold}] ${step} FAIL (see $log)"
        tail -20 "$log"
        exit 1
    fi
}

for f in "${FOLDS[@]}"; do
    onnx_path="artifacts/cnn_medium/onnx/fold_${f}/final.onnx"
    qonnx_path="artifacts/cnn_medium/qonnx/fold_${f}/final_clean.onnx"
    hls_dir="artifacts/cnn_medium/hls/pytorch/fold_${f}"

    run "$f" export_onnx scripts/export_onnx.py --fold "$f"

    run "$f" prepare_qonnx scripts/prepare_qonnx.py \
        --input "$onnx_path" --output "$qonnx_path"

    run "$f" convert_to_hls scripts/convert_to_hls.py \
        --frontend pytorch --fold "$f" \
        --output-dir "$hls_dir" \
        --project-name "cnn_medium_pytorch_hls" \
        --default-precision "fixed<24,8>"

    run "$f" export_calibration scripts/export_calibration_data.py --fold "$f"
done

echo "All folds done."
