#!/usr/bin/env bash
# Build the Coyote simulation testbench (sim/hw/tb_user.sv) with Verilator.
#
# Usage: sim/vl/build.sh <hw build dir> <out dir>
#   <hw build dir>  the hardware build folder where `make sim` ran (what COYOTE_SIM_DIR points to)
#   <out dir>       output folder; the binary is <out dir>/coyote_vl
#
# Run the host program against the binary with:
#   COYOTE_SIM_BIN=<out dir>/coyote_vl COYOTE_SIM_DIR=<hw build dir> ./test ...
#
# Needs the Verilator of sim/vl/verilator.env or newer in PATH, and Vivado in PATH when the xsim scripts
# of this build are missing or older than its vfpga_top.svh (step 0).
# The source list and the include folders come from the xsim project that `make sim` wrote,
# so Verilator compiles the same files as xsim. Vivado derives the list from the hierarchy of the
# top in <hw build dir>/sim/vfpga_top.svh, so step 0 writes it again when the top is newer than
# the list (a Python unit test puts its own top there).
# When <hw build dir> holds files.f and incs.f instead of a Vivado project (written by sim/vl/configure.sh),
# the script takes those lists and needs no Vivado at all.
#
# Environment:
#   JOBS        parallel compile jobs (default: the cores of the machine)
#   VL_DEFINES  preprocessor defines (default "-DEN_RANDOMIZATION -DEN_INTERACTIVE", the C++ cThread flow)
#   VL_MODELS   extra folders with Verilog models of modules Verilator cannot compile (VHDL, encrypted IP),
#               space separated; taken only when a module is missing, like sim/vl/models
#   VL_FLAGS    extra Verilator flags, for example --trace
set -euo pipefail
shopt -s nullglob

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

# Steps 0 to 3: $OUT/files.f and $OUT/incs.f from the xsim project of $HW.
lists_from_xsim_project() {
    local XPR PRJS PRJ XSIM IP_SRCS VHDL_PRJ
    XPR=("$HW"/sim/*.xpr)
    if [ ${#XPR[@]} -ne 1 ]; then
        echo "no simulation project in $HW/sim: run 'make sim' in $HW first" >&2
        exit 1
    fi

    # 0. The xsim scripts. `make sim` creates the project only. The first xsim run writes the compile
    #    scripts (tb_user_vlog.prj lists the sources in compile order) and generates the IP simulation
    #    sources. Vivado writes the list for the hierarchy of the vfpga_top.svh in place at that time,
    #    so let Vivado write the scripts here (batch mode, no compile, about 40 s) when they are missing
    #    or older than the top.
    PRJS=("$HW"/sim/*.sim/sim_1/behav/xsim/tb_user_vlog.prj)
    if [ ${#PRJS[@]} -eq 0 ] || [ "${PRJS[0]}" -ot "$HW/sim/vfpga_top.svh" ]; then
        if ! command -v vivado > /dev/null; then
            echo "the xsim scripts in $HW/sim are missing or older than vfpga_top.svh, and no vivado in PATH to write them" >&2
            exit 1
        fi
        {
            echo "open_project ${XPR[0]}"
            echo "update_compile_order -fileset sources_1"
            echo "launch_simulation -simset [get_filesets sim_1] -mode behavioral -scripts_only"
        } > "$OUT/xsim_scripts.tcl"
        if ! (cd "$OUT" && vivado -mode batch -nolog -nojournal -source xsim_scripts.tcl > xsim_scripts.log 2>&1); then
            grep '^ERROR' "$OUT/xsim_scripts.log" | head -20 >&2
            echo "vivado failed, see $OUT/xsim_scripts.log" >&2
            exit 1
        fi
        PRJS=("$HW"/sim/*.sim/sim_1/behav/xsim/tb_user_vlog.prj)
        if [ ${#PRJS[@]} -eq 0 ]; then
            echo "vivado wrote no tb_user_vlog.prj under $HW/sim, see $OUT/xsim_scripts.log" >&2
            exit 1
        fi
    fi
    PRJ=${PRJS[0]}
    XSIM=$(dirname "$PRJ")

    # 1. The project sources in xsim order, without glbl.v (Xilinx primitives, xsim only).
    grep -oE '"[^"]+\.s?v"' "$PRJ" | tr -d '"' | grep -v 'glbl\.v$' \
        | (cd "$XSIM" && xargs realpath) > "$OUT/files.f"

    # 2. The IP library sources (<ip>/hdl/*.v), which xsim loads precompiled, one copy per file name.
    #    They have `timescale 1ps/1ps and must stay after the 1ns/1ps project sources: Verilator gives
    #    the testbench classes the time unit of the first file.
    IP_SRCS=("$HW"/sim/*.gen/sources_1/ip/*/hdl/*.v)
    if [ ${#IP_SRCS[@]} -gt 0 ]; then
        printf '%s\n' "${IP_SRCS[@]}" | awk -F/ '!seen[$NF]++' >> "$OUT/files.f"
    fi

    # 3. The include folders of the xsim project.
    grep -oE -- '--include "[^"]+"' "$PRJ" | cut -d'"' -f2 | sort -u \
        | (cd "$XSIM" && xargs realpath) | sed 's/^/-I/' > "$OUT/incs.f"

    # VHDL sources of the project: Verilator compiles no VHDL, a Verilog model per entity must come from VL_MODELS.
    VHDL_PRJ=$XSIM/tb_user_vhdl.prj
    if [ -f "$VHDL_PRJ" ] && grep -q '\.vhdl\?"' "$VHDL_PRJ"; then
        echo "note: the project compiles $(grep -c '\.vhdl\?"' "$VHDL_PRJ") VHDL files; Verilator needs Verilog models of their entities (VL_MODELS)"
    fi
}

if [ -f "$HW/files.f" ] && [ -f "$HW/incs.f" ]; then
    # Lists of sim/vl/configure.sh: absolute paths.
    cp "$HW/files.f" "$HW/incs.f" "$OUT/"
else
    lists_from_xsim_project
fi

# 4. Verilator does not parse `1step`. At the time precision of 1 ps, 1ps is the same value.
#    The list takes a patched copy of lynx_pkg.sv in place of the generated one.
LYNX=$(grep -m1 '/lynx_pkg\.sv$' "$OUT/files.f") || { echo "no lynx_pkg.sv in the source list of $HW" >&2; exit 1; }
sed 's/1step/1ps/' "$LYNX" > "$OUT/lynx_pkg.sv"
sed -i "s#.*/lynx_pkg\.sv\$#$OUT/lynx_pkg.sv#" "$OUT/files.f"

# 5. Build. -O1 runs faster than the Verilator default -Os at the same compile time.
#    -Wno-ENUMVALUE: '0 and 'X assigned to enum signals (tie-offs and resets in vFPGA code).
#    file_io.c (the pipe reader, DPI-C) has extern "C" guards and compiles as C++.
#    -y models: simulation models of encrypted Xilinx IP and of VHDL entities, taken only when the module is missing.
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
