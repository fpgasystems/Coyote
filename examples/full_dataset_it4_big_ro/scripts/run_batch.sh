#!/usr/bin/env bash
# Run one batch build end-to-end.
#
# Usage:
#   ./scripts/run_batch.sh STAND_FP09
#
# Each batch exits immediately on any failure and logs every stage.

set -euo pipefail

BATCH="${1:?Usage: $0 <BATCH_ID>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_BASE="$BASE_DIR/builds/$BATCH"
LOG_DIR="$BASE_DIR/logs"

source "$SCRIPT_DIR/source_xilinx_2024_2.sh"

EXPECTED_CONFIGS="$(PYTHONPATH="$SCRIPT_DIR" python3 -c 'from dataset_config import CONFIG_COUNT; print(CONFIG_COUNT)')"

echo "=== Full dataset it4_big_ro: batch $BATCH ==="
echo "  Base dir: $BASE_DIR"
echo "  Build dir: $BUILD_BASE"
echo "  Expected partial bins: $EXPECTED_CONFIGS"
echo "  Start time: $(date)"
START_TIME=$SECONDS

# Step 1: Generate CMakeLists.txt
echo "[1/8] Generating CMakeLists.txt..."
mkdir -p "$BUILD_BASE/hw"
python3 "$SCRIPT_DIR/gen_cmakelists.py" --batch "$BATCH" --output "$BUILD_BASE/hw/CMakeLists.txt"

# Step 2: Create symlinks to shared resources
echo "[2/8] Setting up symlinks..."
ln -sfn "$BASE_DIR/hw/apps"       "$BUILD_BASE/hw/apps"
ln -sfn "$BASE_DIR/hw/floorplans" "$BUILD_BASE/hw/floorplans"

# Step 3: Create build directory and configure
echo "[3/8] Running cmake..."
mkdir -p "$BUILD_BASE/build_hw" "$LOG_DIR"
cd "$BUILD_BASE/build_hw"
cmake ../hw 2>&1 | tee "$LOG_DIR/${BATCH}_cmake.log"

# Step 4-8: Build stages
for stage in project synth link shell app bitgen; do
    STAGE_START=$SECONDS
    echo "[$(date +%H:%M:%S)] Running make $stage..."
    make $stage 2>&1 | tee "$LOG_DIR/${BATCH}_${stage}.log"
    STAGE_DUR=$(( SECONDS - STAGE_START ))
    echo "  make $stage completed in ${STAGE_DUR}s"
done

# Step 9: Verify outputs
echo ""
echo "=== Verification ==="
N_PARTIAL_BINS=$(find bitstreams/ -path '*/config_*/*.bin' -type f 2>/dev/null | wc -l)
N_SHELL_BINS=$(find bitstreams/ -maxdepth 1 -name 'shell_top.bin' -type f 2>/dev/null | wc -l)
echo "  Partial bitstream files found: $N_PARTIAL_BINS (expected: $EXPECTED_CONFIGS)"
echo "  shell_top.bin files found: $N_SHELL_BINS"

TOTAL_DUR=$(( SECONDS - START_TIME ))
echo ""
echo "=== Batch $BATCH completed ==="
echo "  Total time: ${TOTAL_DUR}s ($((TOTAL_DUR / 3600))h $((TOTAL_DUR % 3600 / 60))m)"
echo "  End time: $(date)"

if [ "$N_PARTIAL_BINS" -ne "$EXPECTED_CONFIGS" ]; then
    echo "  WARNING: Expected $EXPECTED_CONFIGS partial .bin files, found $N_PARTIAL_BINS"
    exit 1
fi
