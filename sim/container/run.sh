#!/usr/bin/env bash
# Run the example under Verilator: the host program, then the Python tests of the example
# (sim/unit_test/examples/<example folder>, the UNIT_TEST_DIR of the build; skipped when it has none).
# Usage: run.sh [host program arguments]   (default: -X 1024 -r 1 -s 0)
set -euo pipefail
WORK=${WORK:-/work}
COYOTE=${COYOTE:-/opt/coyote}
export PATH=${PREFIX:-/opt/verilator}/bin:$PATH

if [ $# -eq 0 ]; then
    set -- -X 1024 -r 1 -s 0
fi
cd "$WORK/sw"
COYOTE_SIM_BIN=$WORK/vl_cpp/coyote_vl COYOTE_SIM_DIR=$WORK ./test "$@"
tail -1 "$WORK/sim/coyote_vl.log"

TESTS=$(sed -n 's/^UNIT_TEST_DIR:[A-Z]*=//p' "$WORK/CMakeCache.txt")
if [ -d "$TESTS" ]; then
    COYOTE_SIM_VERILATOR=1 PYTHONPATH=$WORK:$COYOTE/sim python3 -m unittest discover -s "$TESTS"
fi
