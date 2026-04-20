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
CANDIDATE="${CANDIDATE:-}"
DEFAULT_PRECISION="${DEFAULT_PRECISION:-fixed<24,8>}"
CANDIDATE_ARG=()
if [[ -n "$CANDIDATE" ]]; then
    CANDIDATE_ARG=(--candidate "$CANDIDATE")
fi
CANDIDATE_NAME="$(CANDIDATE="$CANDIDATE" "$PY" -c 'import os; from pipeline import get_candidate; print(get_candidate(os.environ.get("CANDIDATE") or None).name)')"
PROJECT_NAME="${PROJECT_NAME:-${CANDIDATE_NAME}_pytorch_hls}"

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
    onnx_path="artifacts/${CANDIDATE_NAME}/onnx/fold_${f}/final.onnx"
    qonnx_path="artifacts/${CANDIDATE_NAME}/qonnx/fold_${f}/final_clean.onnx"
    hls_dir="artifacts/${CANDIDATE_NAME}/hls/pytorch/fold_${f}"

    run "$f" export_onnx scripts/export_onnx.py "${CANDIDATE_ARG[@]}" --fold "$f"

    run "$f" prepare_qonnx scripts/prepare_qonnx.py \
        --input "$onnx_path" --output "$qonnx_path"

    run "$f" convert_to_hls scripts/convert_to_hls.py \
        "${CANDIDATE_ARG[@]}" --frontend pytorch --fold "$f" \
        --output-dir "$hls_dir" \
        --project-name "$PROJECT_NAME" \
        --default-precision "$DEFAULT_PRECISION"

    run "$f" export_calibration scripts/export_calibration_data.py "${CANDIDATE_ARG[@]}" --fold "$f"
done

echo "All folds done."
