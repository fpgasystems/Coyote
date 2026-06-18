#!/usr/bin/env bash
# Run one isolated single-bitstream job.

set -euo pipefail

if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <job_id> <global_config> <batch_id> <fp_id> <fplan_file> <config_local> <ro_count> <target_pct>"
    exit 2
fi

JOB_ID="$1"
GLOBAL_CONFIG="$2"
BATCH_ID="$3"
FP_ID="$4"
FPLAN_FILE="$5"
CONFIG_LOCAL="$6"
RO_COUNT="$7"
TARGET_PCT="$8"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
JOB_ROOT="${JOB_ROOT:-jobs}"
PART="$(PYTHONPATH="$SCRIPT_DIR" python3 - "$GLOBAL_CONFIG" <<'PY'
import sys
from job_paths import part_for_global_config
print(part_for_global_config(int(sys.argv[1])))
PY
)"
JOB_BASE="$BASE_DIR/$JOB_ROOT/$PART/$JOB_ID"
BUILD_HW="$JOB_BASE/build_hw"
LOG_DIR="$BASE_DIR/logs/$JOB_ROOT/$PART"

source "$SCRIPT_DIR/source_xilinx_2024_2.sh"

mkdir -p "$JOB_BASE/hw" "$BUILD_HW" "$LOG_DIR"

echo "=== Job $JOB_ID ==="
echo "  Part: $PART"
echo "  Job root: $JOB_ROOT"
echo "  Global config: $GLOBAL_CONFIG"
echo "  Source batch: $BATCH_ID"
echo "  Floorplan: $FP_ID ($FPLAN_FILE)"
echo "  Original config: $CONFIG_LOCAL"
echo "  ROs: $RO_COUNT"
echo "  Target percent: $TARGET_PCT"
echo "  Start time: $(date)"

python3 "$SCRIPT_DIR/gen_single_job_cmake.py" \
    --job-id "$JOB_ID" \
    --batch-id "$BATCH_ID" \
    --fp-id "$FP_ID" \
    --fplan-file "$FPLAN_FILE" \
    --config-local "$CONFIG_LOCAL" \
    --ro-count "$RO_COUNT" \
    --output "$JOB_BASE/hw/CMakeLists.txt"

ln -sfn "$BASE_DIR/hw/apps" "$JOB_BASE/hw/apps"
ln -sfn "$BASE_DIR/hw/floorplans" "$JOB_BASE/hw/floorplans"

cat > "$JOB_BASE/job_info.tsv" <<EOF
job_id	$JOB_ID
global_config	$GLOBAL_CONFIG
batch_id	$BATCH_ID
fp_id	$FP_ID
fplan_file	$FPLAN_FILE
config_local	$CONFIG_LOCAL
ro_count	$RO_COUNT
target_pct	$TARGET_PCT
EOF

cd "$BUILD_HW"
cmake ../hw

for stage in project synth link shell app bitgen; do
    echo "[$(date +%H:%M:%S)] make $stage"
    make "$stage"
done

BIN="bitstreams/config_0/vfpga_c0_0.bin"
if [ ! -f "$BIN" ]; then
    echo "ERROR: expected bin not found: $BUILD_HW/$BIN"
    exit 1
fi

echo "=== Job $JOB_ID completed ==="
echo "  Bin: $BUILD_HW/$BIN"
echo "  End time: $(date)"
