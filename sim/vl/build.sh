#!/usr/bin/env bash
# Build the Coyote simulation testbench (sim/hw/tb_user.sv) with Verilator.
#
# Usage: sim/vl/build.sh <hw build dir> <out dir>
#   <hw build dir>  the build folder that sim/vl/configure.sh made (what COYOTE_SIM_DIR points to)
#   <out dir>       output folder; the binary is <out dir>/coyote_vl
#
# Run the host program against the binary with:
#   COYOTE_SIM_BIN=<out dir>/coyote_vl COYOTE_SIM_DIR=<hw build dir> ./test ...
#
# Needs the Verilator of sim/vl/verilator.env or newer in PATH. The source list and the include
# folders are files.f and incs.f of <hw build dir>. No Vivado is needed.
#
# Environment:
#   JOBS        parallel compile jobs (default: the cores of the machine)
#   VL_DEFINES  preprocessor defines (default "-DEN_RANDOMIZATION -DEN_INTERACTIVE", the C++ cThread flow)
#   VL_MODELS   extra folders with Verilog models of modules Verilator cannot compile (VHDL, Xilinx IP),
#               space separated; taken only when a module is missing, like sim/vl/models
#   VL_FLAGS    extra Verilator flags, for example --trace
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "usage: $0 <hw build dir> <out dir>" >&2
    exit 1
fi

HW=$(realpath "$1")
mkdir -p "$2"
OUT=$(realpath "$2")
VL=$(realpath "$(dirname "$0")")
DPI=$(realpath "$VL/../hw/dpi")

# The pin. sort -V orders a tag before the master builds after it (v5.052 < v5.052-N < v5.053).
. "$VL/verilator.env"
command -v verilator > /dev/null || { echo "verilator not found in PATH (needs $VERILATOR_MIN or newer, see $VL/verilator.env)" >&2; exit 1; }
VL_REV=$(verilator_rev)
if [ -z "$VL_REV" ] || [ "$(printf '%s\n' "$VERILATOR_MIN" "$VL_REV" | sort -V | head -n 1)" != "$VERILATOR_MIN" ]; then
    echo "Verilator ${VL_REV:-(unknown version)} is too old, needs $VERILATOR_MIN or newer (sim/vl/install_verilator.sh builds it)" >&2
    exit 1
fi

# 1. The lists of sim/vl/configure.sh: absolute paths.
if [ ! -f "$HW/files.f" ] || [ ! -f "$HW/incs.f" ]; then
    echo "no files.f and incs.f in $HW: run sim/vl/configure.sh first" >&2
    exit 1
fi
cp "$HW/files.f" "$HW/incs.f" "$OUT/"

# 2. Verilator does not parse `1step`. At the time precision of 1 ps, 1ps is the same value.
#    The list takes a patched copy of lynx_pkg.sv in place of the generated one.
LYNX=$(grep -m1 '/lynx_pkg\.sv$' "$OUT/files.f") || { echo "no lynx_pkg.sv in the source list of $HW" >&2; exit 1; }
sed 's/1step/1ps/' "$LYNX" > "$OUT/lynx_pkg.sv"
sed -i "s#.*/lynx_pkg\.sv\$#$OUT/lynx_pkg.sv#" "$OUT/files.f"

# 3. Build. -O1 runs faster than the Verilator default -Os at the same compile time.
#    -Wno-ENUMVALUE: '0 and 'X assigned to enum signals (tie-offs and resets in vFPGA code).
#    file_io.c (the pipe reader, DPI-C) has extern "C" guards and compiles as C++.
#    -y models: simulation models of Xilinx IP and of VHDL entities, taken only when the module is missing.
MODEL_DIRS=(-y "$VL/models")
for d in ${VL_MODELS:-}; do
    MODEL_DIRS+=(-y "$(realpath "$d")")
done
# shellcheck disable=SC2086
if ! verilator --binary --timing -j "${JOBS:-$(nproc)}" -CFLAGS -O1 \
        -Wno-fatal -Wno-lint -Wno-style -Wno-ENUMVALUE \
        ${VL_DEFINES:--DEN_RANDOMIZATION -DEN_INTERACTIVE} ${VL_FLAGS:-} \
        "${MODEL_DIRS[@]}" \
        -f "$OUT/incs.f" -f "$OUT/files.f" "$DPI/file_io.c" \
        --top-module tb_user --Mdir "$OUT/obj" -o coyote_vl > "$OUT/build.log" 2>&1; then
    grep '^%Error' "$OUT/build.log" | head -20 >&2
    echo "verilator failed, see $OUT/build.log" >&2
    exit 1
fi

ln -sfn obj/coyote_vl "$OUT/coyote_vl"
tail -1 "$OUT/build.log"
echo "$OUT/coyote_vl"
