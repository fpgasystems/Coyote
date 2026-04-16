#!/usr/bin/env bash
# Run one batch build end-to-end.
#
# Usage:
#   ./scripts/run_batch.sh BENIGN_FP10
#   ./scripts/run_batch.sh STAND_FP13
#
# Each batch:
#   1. Generates CMakeLists.txt from template
#   2. Creates symlinks to shared apps/ and floorplans/
#   3. Runs cmake + make project/synth/link/shell/app/bitgen
#   4. Logs each stage to logs/<BATCH>_<stage>.log
#   5. Exits immediately on any failure

set -euo pipefail

BATCH="${1:?Usage: $0 <BATCH_ID>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_BASE="$BASE_DIR/builds/$BATCH"
LOG_DIR="$BASE_DIR/logs"

echo "=== Full dataset it3: batch $BATCH ==="
echo "  Base dir: $BASE_DIR"
echo "  Build dir: $BUILD_BASE"
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
N_BINS=$(find bitstreams/ -name "*.bin" 2>/dev/null | wc -l)
echo "  Bitstream files found: $N_BINS (expected: 15)"

TOTAL_DUR=$(( SECONDS - START_TIME ))
echo ""
echo "=== Batch $BATCH completed ==="
echo "  Total time: ${TOTAL_DUR}s ($((TOTAL_DUR / 3600))h $((TOTAL_DUR % 3600 / 60))m)"
echo "  End time: $(date)"

if [ "$N_BINS" -ne 15 ]; then
    echo "  WARNING: Expected 15 .bin files, found $N_BINS"
    exit 1
fi
