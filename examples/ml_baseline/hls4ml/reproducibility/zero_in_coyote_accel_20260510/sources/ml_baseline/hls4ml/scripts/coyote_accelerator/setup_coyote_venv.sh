#!/usr/bin/env bash
set -euo pipefail

ML_BASELINE_ROOT="${ML_BASELINE_ROOT:-/pub/scratch/sdeheredia/Coyote/examples/ml_baseline}"
BASE_VENV="${BASE_VENV:-${ML_BASELINE_ROOT}/.venv_hls4ml}"
COYOTE_VENV="${COYOTE_VENV:-${ML_BASELINE_ROOT}/.venv_hls4ml_coyote}"
HLS4ML_PR_DIR="${HLS4ML_PR_DIR:-/mnt/scratch/sdeheredia/hls4ml}"
REQ_DIR="${REQ_DIR:-${ML_BASELINE_ROOT}/hls4ml/artifacts/coyote_accelerator_zero_in/venv}"

BASE_PY="${BASE_VENV}/bin/python"
COYOTE_PY="${COYOTE_VENV}/bin/python"

if [[ ! -x "${BASE_PY}" ]]; then
  echo "missing base venv python: ${BASE_PY}" >&2
  exit 1
fi

if [[ -e "${COYOTE_VENV}" ]]; then
  echo "refusing to overwrite existing venv: ${COYOTE_VENV}" >&2
  exit 1
fi

if [[ ! -d "${HLS4ML_PR_DIR}/hls4ml/backends/coyote_accelerator" ]]; then
  echo "CoyoteAccelerator backend is missing under ${HLS4ML_PR_DIR}" >&2
  exit 1
fi

cd "${HLS4ML_PR_DIR}"
git submodule update --init --recursive
if git submodule status --recursive | awk '$1 ~ /^-/ { bad=1 } END { exit bad ? 1 : 0 }'; then
  :
else
  echo "one or more hls4ml submodules are still uninitialized" >&2
  git submodule status --recursive >&2
  exit 1
fi

mkdir -p "${REQ_DIR}"
"${BASE_PY}" -m pip freeze \
  | grep -v -E '^(hls4ml==|hls4ml @ |-e .*(hls4ml|Coyote))' \
  | grep -v -E '^(torch|torchvision|torchaudio|triton|nvidia-[^=]+|brevitas|unfoldNd)==' \
  | grep -v -E '\+cu[0-9]+' \
  > "${REQ_DIR}/requirements_from_venv_hls4ml.txt"

"${BASE_PY}" -m venv "${COYOTE_VENV}"
"${COYOTE_PY}" -m pip install --upgrade pip setuptools wheel
"${COYOTE_PY}" -m pip install -r "${REQ_DIR}/requirements_from_venv_hls4ml.txt"
"${COYOTE_PY}" - <<'PY' || "${COYOTE_PY}" -m pip install torchvision==0.21.0
import torchvision.transforms.functional  # noqa: F401
PY
"${COYOTE_PY}" -m pip install -e "${HLS4ML_PR_DIR}"

"${COYOTE_PY}" - <<'PY'
import hls4ml
from hls4ml.converters import convert_from_keras_model
from hls4ml.utils import config_from_keras_model
from hls4ml.backends.coyote_accelerator.coyote_accelerator_overlay import CoyoteOverlay

print(f"hls4ml_path={list(getattr(hls4ml, '__path__', []))}")
print(f"converter={convert_from_keras_model.__name__}")
print(f"config={config_from_keras_model.__name__}")
print(f"overlay={CoyoteOverlay.__name__}")
if not any("sdeheredia/hls4ml" in path for path in getattr(hls4ml, "__path__", [])):
    raise SystemExit(f"editable hls4ml path is not the PR checkout: {getattr(hls4ml, '__path__', None)}")
PY
