#!/usr/bin/env bash
# Make the simulation build folder of a Coyote application for sim/vl/build.sh, without Vivado.
#
# Usage: sim/vl/configure.sh <app hw dir> <work dir> [cmake args ...]
#   <app hw dir>  the CMake project of the application hardware (with load_apps and create_hw)
#   <work dir>    the build folder to create (what build.sh and COYOTE_SIM_DIR take)
#   cmake args    passed to the configure, for example -DFDEV_NAME=u55c
#
# The steps of `make sim` that need no Vivado:
#   1. The CMake configure with -DSKIP_XILINX=1: FindCoyoteHW.cmake then accepts a missing Vivado and
#      Vitis HLS and skips the network stack folder (its HLS cores
#      need Vitis HLS at configure time). It writes base.tcl, write_hdl.py, cr_sim.tcl and
#      coyote_test/__init__.py from the configuration of the application.
#   2. write_hdl.py 3 0 0 renders sim/lynx_pkg.sv and sim/user_logic_c0_0.sv (needs python3 with jinja2).
#   3. The vFPGA folders of configuration 0, region 0 (the limit of cr_sim.tcl as well) come from
#      cr_sim.tcl; vfpga_top.svh of the first one goes to sim/. When a vFPGA folder has SpinalHDL
#      kernels (spinal/), comp_spinal.tcl writes their Verilog, run with tclsh in place of Vivado
#      (needs sbt and Java 11 or newer in PATH).
#   4. files.f: every .sv under the hdl/ folder of each vFPGA folder, the Coyote packages and
#      testbench, the SpinalHDL Verilog, and the two rendered files, the packages first. Verilator
#      keeps only what tb_user reaches. incs.f: every folder of these trees that holds a .svh or .vh file, and the folders of
#      hw/hdl/common as libraries (an -I folder is also a module library in Verilator; -y is the same option).
# Not supported: HLS kernels (they need Vitis HLS). Xilinx IP needs a Verilog model in
# sim/vl/models or VL_MODELS of build.sh.
#
# Then: sim/vl/build.sh <work dir> <out dir>
set -euo pipefail

if [ $# -lt 2 ]; then
    echo "usage: $0 <app hw dir> <work dir> [cmake args ...]" >&2
    exit 1
fi
APP=$(realpath "$1")
mkdir -p "$2"
WORK=$(realpath "$2")
shift 2
VL=$(realpath "$(dirname "$0")")

# 1. Configure without Vivado and Vitis HLS. EN_XTERM=0: the Tcl scripts write to logs, and their colour
#    codes need tput and a TERM, which a CI runner does not have.
if ! cmake -S "$APP" -B "$WORK" -DSKIP_XILINX=1 -DEN_XTERM=0 "$@" > "$WORK/configure.log" 2>&1; then
    tail -20 "$WORK/configure.log" >&2
    echo "cmake failed, see $WORK/configure.log" >&2
    exit 1
fi
# The Coyote checkout the application builds against (its CYT_DIR), which need not be this one.
CYT=$(realpath "$(sed -n 's/^set root_dir *"\(.*\)"$/\1/p' "$WORK/base.tcl")")

# 2. The two generated sources, as cr_sim.tcl renders them.
mkdir -p "$WORK/sim"
(cd "$WORK" && python3 write_hdl.py 3 0 0 > render.log)

# 3. The vFPGA folders of configuration 0, region 0, relative to the application (load_apps).
read -r -a DIRS <<< "$(sed -n 's/^set vfpga_c0_0 "\(.*\)"$/\1/p' "$WORK/cr_sim.tcl")"
[ ${#DIRS[@]} -gt 0 ] || { echo "no vfpga_c0_0 folders in $WORK/cr_sim.tcl" >&2; exit 1; }
for i in "${!DIRS[@]}"; do
    DIRS[i]=$(realpath "$APP/${DIRS[i]}")
    [ ! -d "${DIRS[i]}/hls" ] || { echo "${DIRS[i]}/hls: HLS kernels need Vitis HLS, not supported here" >&2; exit 1; }
    [ ! -d "${DIRS[i]}/spinal" ] || HAS_SPINAL=1
done
cp "${DIRS[0]}/vfpga_top.svh" "$WORK/sim/"
# The folder where comp_spinal.tcl puts the Verilog of configuration 0, region 0 (cr_sim.tcl adds the same folder).
PROJECT=$(sed -n 's/^set project *"\(.*\)"$/\1/p' "$WORK/base.tcl")
SPINAL=$WORK/${PROJECT}_config_0/user_c0_0/hdl/ext/spinal
if [ -n "${HAS_SPINAL:-}" ] && ! (cd "$WORK" && tclsh comp_spinal.tcl > spinal.log 2>&1); then
    tail -20 "$WORK/spinal.log" >&2
    echo "SpinalHDL generation failed, see $WORK/spinal.log" >&2
    exit 1
fi

# 4. The file lists. Some files of hw/hdl/common do not parse on their own, so its folders are
#    libraries: Verilator reads <module>.sv there only for a module the design uses. A file
#    whose module has another name cannot be found that way and is listed.
#    files.f takes the hdl/ folder of a vFPGA folder, incs.f the vFPGA folder itself (vfpga_top.svh).
COMMON=$CYT/hw/hdl/common
TREES=("$CYT/hw/hdl/pkg" "$CYT/sim/hw")
for d in "${DIRS[@]}"; do
    [ -d "$d/hdl" ] && TREES+=("$d/hdl")
done
# The rendered files last: the user logic wrapper includes vfpga_top.svh, which may use macros that
# the design files define (Verilator keeps a define for the files after it).
{
    find "${TREES[@]}" -name "*.sv" | sort
    find "$COMMON" -name "*.sv" | sort | while read -r f; do
        grep -qE "^\s*module\s+$(basename "$f" .sv)\b" "$f" || echo "$f"
    done
    [ ! -d "$SPINAL" ] || find "$SPINAL" -name "*.v" | sort
    ls "$WORK"/sim/*.sv
} | python3 "$VL/order_sources.py" > "$WORK/files.f"
{
    echo "-I$WORK/sim"
    find "${TREES[@]}" "$COMMON" "${DIRS[@]}" \
        \( -name "*.svh" -o -name "*.vh" -o \( -path "$COMMON/*" -name "*.sv" \) \) -printf '-I%h\n' | sort -u
} > "$WORK/incs.f"
echo "$WORK: $(wc -l < "$WORK/files.f") sources, $(wc -l < "$WORK/incs.f") include and library folders"
echo "build with: $VL/build.sh $WORK <out dir>"
