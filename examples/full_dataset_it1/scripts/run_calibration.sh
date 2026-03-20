#!/usr/bin/env bash
# Run floorplan calibration builds.
#
# For each of 7 candidate floorplans, runs 3 test builds:
#   1. A02_hls_vadd (medium benign)
#   2. A03_multitenancy_aes (large benign)
#   3. ro_5000 (largest standalone)
#
# Pass criteria: all 3 builds complete with timing PASS (WNS > 0).
# Promote top 5 candidates that pass all 3 tests.
#
# Usage:
#   ./scripts/run_calibration.sh [FP_ID]   # run one floorplan, e.g., FP03
#   ./scripts/run_calibration.sh all        # run all 7 candidates

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CAL_DIR="$BASE_DIR/builds/calibration"
LOG_DIR="$BASE_DIR/logs/calibration"

FLOORPLANS=(FP00 FP01 FP02 FP03 FP04 FP05 FP06)
TEST_APPS=("benign/A02_hls_vadd" "benign/A03_multitenancy_aes" "standalone/ro_5000")
TEST_NAMES=("vadd" "aes" "ro5000")

run_calibration_build() {
    local FP_ID="$1"
    local APP_PATH="$2"
    local TEST_NAME="$3"
    local BUILD_ID="cal_${FP_ID}_${TEST_NAME}"
    local BUILD_DIR="$CAL_DIR/$BUILD_ID"

    echo ""
    echo "--- Calibration: $FP_ID + $TEST_NAME ---"
    echo "  Build dir: $BUILD_DIR"
    echo "  Start: $(date)"

    mkdir -p "$BUILD_DIR/hw" "$LOG_DIR"

    # Generate minimal CMakeLists.txt (1 config)
    cat > "$BUILD_DIR/hw/CMakeLists.txt" << CMAKE_EOF
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR \${CMAKE_SOURCE_DIR}/../../../../../)
set(CMAKE_MODULE_PATH \${CMAKE_MODULE_PATH} \${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(${BUILD_ID})

set(FDEV_NAME   "u55c")
set(N_REGIONS   1)
set(EN_PR       1)
set(N_CONFIG    1)
set(EN_STRM     1)
set(N_STRM_AXI  2)
set(EN_MEM      0)
set(FPLAN_PATH "\${CMAKE_SOURCE_DIR}/floorplans/${FP_ID}*.xdc")

validation_checks_hw()

load_apps(
    VFPGA_C0_0   "apps/${APP_PATH}"
)

create_hw()
CMAKE_EOF

    # Symlinks
    ln -sfn "$BASE_DIR/hw/apps"       "$BUILD_DIR/hw/apps"
    ln -sfn "$BASE_DIR/hw/floorplans" "$BUILD_DIR/hw/floorplans"

    # Fix FPLAN_PATH to use exact filename
    local FPLAN_FILE
    FPLAN_FILE=$(ls "$BASE_DIR/hw/floorplans/${FP_ID}"*.xdc 2>/dev/null | head -1)
    FPLAN_FILE=$(basename "$FPLAN_FILE")
    sed -i "s|${FP_ID}\*\.xdc|${FPLAN_FILE}|" "$BUILD_DIR/hw/CMakeLists.txt"

    # Build
    mkdir -p "$BUILD_DIR/build_hw"
    cd "$BUILD_DIR/build_hw"

    local STAGE_START=$SECONDS
    cmake ../hw                    > "$LOG_DIR/${BUILD_ID}_cmake.log"   2>&1
    make project                   > "$LOG_DIR/${BUILD_ID}_project.log" 2>&1
    make synth                     > "$LOG_DIR/${BUILD_ID}_synth.log"   2>&1
    make link                      > "$LOG_DIR/${BUILD_ID}_link.log"    2>&1
    make shell                     > "$LOG_DIR/${BUILD_ID}_shell.log"   2>&1
    make app                       > "$LOG_DIR/${BUILD_ID}_app.log"     2>&1
    make bitgen                    > "$LOG_DIR/${BUILD_ID}_bitgen.log"  2>&1
    local DUR=$(( SECONDS - STAGE_START ))

    # Check result
    local N_BINS
    N_BINS=$(find bitstreams/ -name "*.bin" 2>/dev/null | wc -l)

    if [ "$N_BINS" -eq 1 ]; then
        echo "  PASS: $BUILD_ID (${DUR}s, 1 .bin file)"
        echo "PASS ${DUR}s" > "$LOG_DIR/${BUILD_ID}_result.txt"
    else
        echo "  FAIL: $BUILD_ID (expected 1 .bin, found $N_BINS)"
        echo "FAIL" > "$LOG_DIR/${BUILD_ID}_result.txt"
    fi
}

if [ "${1:-all}" = "all" ]; then
    echo "=== Floorplan calibration: all 7 candidates ==="
    for fp in "${FLOORPLANS[@]}"; do
        for i in "${!TEST_APPS[@]}"; do
            run_calibration_build "$fp" "${TEST_APPS[$i]}" "${TEST_NAMES[$i]}" || true
        done
    done

    # Summary
    echo ""
    echo "=== Calibration Summary ==="
    for fp in "${FLOORPLANS[@]}"; do
        PASS_COUNT=0
        for tn in "${TEST_NAMES[@]}"; do
            RESULT_FILE="$LOG_DIR/cal_${fp}_${tn}_result.txt"
            if [ -f "$RESULT_FILE" ] && grep -q "^PASS" "$RESULT_FILE"; then
                PASS_COUNT=$((PASS_COUNT + 1))
            fi
        done
        if [ "$PASS_COUNT" -eq 3 ]; then
            echo "  $fp: ALL PASS ($PASS_COUNT/3) — PROMOTE"
        else
            echo "  $fp: $PASS_COUNT/3 passed — DISCARD"
        fi
    done
else
    FP_ID="$1"
    for i in "${!TEST_APPS[@]}"; do
        run_calibration_build "$FP_ID" "${TEST_APPS[$i]}" "${TEST_NAMES[$i]}"
    done
fi
