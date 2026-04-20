#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <tag> <default_precision> <reuse_factor> [dense_precision|-] [accum_precision|-]" >&2
  exit 2
fi

TAG="$1"
DEFAULT_PRECISION="$2"
REUSE_FACTOR="$3"
DENSE_PRECISION="${4:--}"
ACCUM_PRECISION="${5:--}"

CANDIDATE="${CANDIDATE:-cnn_small_hls_opt_img512}"
FOLD="${FOLD:-0}"
N_SAMPLES="${N_SAMPLES:-48}"
POOL_ACCUM_PRECISION="${POOL_ACCUM_PRECISION:-fixed<40,20>}"
PROJECT_NAME="${PROJECT_NAME:-${CANDIDATE}_${TAG}_pytorch_hls}"
PY="${PY:-../../ml_baseline/.venv_hls4ml/bin/python}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p logs

set +u
source /tools/Xilinx/Vivado/2024.2/settings64.sh
source /tools/Xilinx/Vitis/2024.2/settings64.sh
source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh
set -u

HLS_SUBDIR="pytorch_${TAG}"
PROJECT_DIR="artifacts/${CANDIDATE}/hls/${HLS_SUBDIR}/fold_${FOLD}"
PARITY_DIR="artifacts/${CANDIDATE}/hls/parity_${TAG}"
RUN_NOTE="${PROJECT_DIR}/run_note.txt"

mkdir -p "$PROJECT_DIR" "$PARITY_DIR"

echo "[${TAG}] start $(date -Is)"
echo "[${TAG}] default=${DEFAULT_PRECISION} dense=${DENSE_PRECISION} accum=${ACCUM_PRECISION} rf=${REUSE_FACTOR}"

METADATA="artifacts/${CANDIDATE}/exports/fold_${FOLD}/metadata.csv"
if [ ! -f "$METADATA" ] || [ "$(($(wc -l < "$METADATA") - 1))" -lt "$N_SAMPLES" ]; then
  "$PY" scripts/export_calibration_data.py \
    --candidate "$CANDIDATE" \
    --fold "$FOLD" \
    --max-samples "$N_SAMPLES"
else
  echo "[${TAG}] calibration bundle already has at least ${N_SAMPLES} samples"
fi

convert_args=(
  scripts/convert_to_hls.py
  --candidate "$CANDIDATE"
  --fold "$FOLD"
  --output-dir "$PROJECT_DIR"
  --project-name "$PROJECT_NAME"
  --reuse-factor "$REUSE_FACTOR"
  --default-precision "$DEFAULT_PRECISION"
  --pool-accum-precision "$POOL_ACCUM_PRECISION"
  --device cpu
)
if [ "$DENSE_PRECISION" != "-" ]; then
  convert_args+=(--dense-precision "$DENSE_PRECISION")
fi
if [ "$ACCUM_PRECISION" != "-" ]; then
  convert_args+=(--accum-precision "$ACCUM_PRECISION")
fi
"$PY" "${convert_args[@]}"

perl -0pi -e 's/csim\s+1/csim       0/; s/cosim\s+1/cosim      0/; s/validation\s+1/validation 0/' \
  "${PROJECT_DIR}/build_opt.tcl"

parity_args=(
  scripts/check_parity.py
  --candidate "$CANDIDATE"
  --folds "$FOLD"
  --n-samples "$N_SAMPLES"
  --hls-subdir "$HLS_SUBDIR"
  --out "$PARITY_DIR"
  --project-name "$PROJECT_NAME"
  --default-precision "$DEFAULT_PRECISION"
  --pool-accum-precision "$POOL_ACCUM_PRECISION"
  --reuse-factor "$REUSE_FACTOR"
  --profile-fold -1
)
if [ "$DENSE_PRECISION" != "-" ]; then
  parity_args+=(--dense-precision "$DENSE_PRECISION")
fi
if [ "$ACCUM_PRECISION" != "-" ]; then
  parity_args+=(--accum-precision "$ACCUM_PRECISION")
fi
"$PY" "${parity_args[@]}"

perl -0pi -e 's/csim\s+1/csim       0/; s/cosim\s+1/cosim      0/; s/validation\s+1/validation 0/' \
  "${PROJECT_DIR}/build_opt.tcl"

SIGN_MISMATCHES="$("$PY" - "$PARITY_DIR/fold_${FOLD}/parity.csv" <<'PY'
import csv
import sys

path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="")))
mismatches = [
    row for row in rows
    if (float(row["pytorch_logit"]) >= 0.0) != (float(row["hls_logit"]) >= 0.0)
]
print(len(mismatches))
PY
)"

{
  echo "tag=${TAG}"
  echo "candidate=${CANDIDATE}"
  echo "fold=${FOLD}"
  echo "default_precision=${DEFAULT_PRECISION}"
  echo "dense_precision=${DENSE_PRECISION}"
  echo "accum_precision=${ACCUM_PRECISION}"
  echo "pool_accum_precision=${POOL_ACCUM_PRECISION}"
  echo "reuse_factor=${REUSE_FACTOR}"
  echo "n_samples=${N_SAMPLES}"
  echo "sign_mismatches=${SIGN_MISMATCHES}"
  echo "project_dir=${PROJECT_DIR}"
  echo "parity_dir=${PARITY_DIR}"
} > "$RUN_NOTE"

if [ "$SIGN_MISMATCHES" != "0" ]; then
  echo "[${TAG}] parity sign mismatches=${SIGN_MISMATCHES}; skipping csynth"
  exit 0
fi

echo "[${TAG}] parity sign check passed; starting csynth $(date -Is)"
(
  cd "$PROJECT_DIR"
  vitis_hls -f build_prj.tcl
) 2>&1 | tee "logs/csynth_${CANDIDATE}_${TAG}_fold${FOLD}.log"

echo "[${TAG}] done $(date -Is)"
