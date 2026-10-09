#!/usr/bin/env bash
# Synthesises rdma_meta_tx_arbiter for two vFPGAs (MULT_REGIONS), out of context on the U55C part,
# and fails if synthesis infers a latch (Synth 8-327): its paths would escape timing analysis. The
# package comes from a two-vFPGA configuration. Needs cmake, python3 (jinja2) and Vivado in PATH.
#   sim/tests/rdma_meta_tx_arbiter/run.sh
set -euo pipefail

TEST_DIR=$(cd "$(dirname "$0")" && pwd)
CYT_DIR=$(cd "$TEST_DIR/../../.." && pwd)
HDL=$CYT_DIR/hw/hdl
BUILD=$TEST_DIR/build

rm -rf "$BUILD" && mkdir -p "$BUILD/prj/src0" "$BUILD/prj/src1"
touch "$BUILD/prj/src0/vfpga_top.svh" "$BUILD/prj/src1/vfpga_top.svh"
cat > "$BUILD/prj/CMakeLists.txt" <<CMAKE
cmake_minimum_required(VERSION 3.5)
set(CYT_DIR $CYT_DIR)
set(CMAKE_MODULE_PATH \${CMAKE_MODULE_PATH} \${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)
project(test_rdma_meta_tx_arbiter)
set(EN_STRM 1)
set(N_REGIONS 2)
validation_checks_hw()
load_apps(VFPGA_C0_0 "src0" VFPGA_C0_1 "src1")
create_hw()
CMAKE
cmake -S "$BUILD/prj" -B "$BUILD/cfg" -DFDEV_NAME=u55c > "$BUILD/cmake.log" 2>&1
mkdir -p "$BUILD/cfg/sim" && (cd "$BUILD/cfg" && python3 write_hdl.py 3 0 0 > write_hdl.log)

cd "$BUILD"
vivado -mode batch -nojournal -log synth.log -source "$TEST_DIR/synth.tcl" -tclargs \
    cfg/sim/lynx_pkg.sv "$HDL/pkg/axi_intf.sv" "$HDL/pkg/lynx_intf.sv" "$HDL/common/queues/fifo.sv" \
    "$HDL/common/queues/queue_stream.sv" "$TEST_DIR/ip_stubs.sv" "$HDL/network/rdma/rdma_meta_tx_arbiter.sv" \
    "$TEST_DIR/synth_top.sv" > /dev/null 2>&1 || true
if grep '^ERROR' synth.log; then exit 1; fi
if grep 'Synth 8-327' synth.log; then exit 1; fi
echo "no latch inferred"
