#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

timestamp="$(date +%Y%m%d_%H%M%S)"
OUT_ARG="${1:-artifacts/diagnostics/rom_existing_coyote_fast_relaunch_${timestamp}}"
OUT="$(python - "$OUT_ARG" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
LOGS="$OUT/logs"
STATUS_DIR="$OUT/status"
TOPIC="coyote-build-sdeheredia"
PY="../.venv_hls4ml/bin/python"

SAMPLE_U55C="$ROOT/artifacts/diagnostics/rom_cnn_20260505_120214/rom_sample0_aclk100/fold_0/u55c_deployment"
ZERO_U55C="$ROOT/artifacts/diagnostics/rom_cnn_20260505_120214/rom_zero_aclk100/fold_0/u55c_deployment"

mkdir -p "$LOGS" "$STATUS_DIR"
LOG="$LOGS/existing_coyote_fast_relaunch.log"
STATUS="$STATUS_DIR/existing_coyote_fast_relaunch.status"

notify() {
    curl -s -d "$*" "ntfy.sh/$TOPIC" >/dev/null || true
}

on_exit() {
    rc=$?
    status="passed"
    if [[ $rc -ne 0 ]]; then status="failed"; fi
    printf '%s rc=%s finished_at=%s log=%s\n' "$status" "$rc" "$(date --iso-8601=seconds)" "$LOG" > "$STATUS"
    notify "rom_existing_coyote_fast_relaunch ${status} rc=${rc} out=${OUT} log=${LOG}"
    exit "$rc"
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1

echo "[$(date --iso-8601=seconds)] starting fast existing ROM Coyote relaunch"
echo "out=$OUT"

echo "[$(date --iso-8601=seconds)] running sample0 Coyote sim with existing simulator"
"$PY" scripts/run_coyote_sim_diagnostic.py \
  --u55c-root "$SAMPLE_U55C" \
  --work-dir "$OUT/existing_rom_sample0_coyote_sim" \
  --mode rom \
  --sample-index 0 \
  --expected-raw -2462 \
  --randomization both \
  --skip-sim-build

if [[ -f "$ZERO_U55C/coyote_hw/build_u55c/sim/coyote_sim.so" ]]; then
  zero_build_arg=(--skip-sim-build)
  echo "[$(date --iso-8601=seconds)] running zero Coyote sim with existing simulator"
else
  zero_build_arg=()
  echo "[$(date --iso-8601=seconds)] zero simulator is missing; building zero Coyote sim"
fi

"$PY" scripts/run_coyote_sim_diagnostic.py \
  --u55c-root "$ZERO_U55C" \
  --work-dir "$OUT/existing_rom_zero_coyote_sim" \
  --mode rom \
  --sample-index 0 \
  --expected-raw 4778 \
  --zero-stream-input \
  --randomization both \
  "${zero_build_arg[@]}"

echo "[$(date --iso-8601=seconds)] fast existing ROM Coyote relaunch complete"
