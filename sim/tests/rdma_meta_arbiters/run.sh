#!/usr/bin/env bash
# Simulates rdma_meta_tx_arbiter and rdma_meta_rx_arbiter with two vFPGAs (MULT_REGIONS) against
# tb_rdma_meta_arbiters.sv with xsim. The package comes from a two-vFPGA configuration. Needs cmake,
# python3 (jinja2) and Vivado's xsim in PATH.
#   sim/tests/rdma_meta_arbiters/run.sh
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
project(test_rdma_meta_arbiters)
set(EN_STRM 1)
set(N_REGIONS 2)
validation_checks_hw()
load_apps(VFPGA_C0_0 "src0" VFPGA_C0_1 "src1")
create_hw()
CMAKE
cmake -S "$BUILD/prj" -B "$BUILD/cfg" -DFDEV_NAME=u55c > "$BUILD/cmake.log" 2>&1
mkdir -p "$BUILD/cfg/sim" && (cd "$BUILD/cfg" && python3 write_hdl.py 3 0 0 > write_hdl.log)

cd "$BUILD"
xvlog -sv -i "$HDL/pkg" cfg/sim/lynx_pkg.sv "$HDL/pkg/axi_intf.sv" "$HDL/pkg/lynx_intf.sv" \
    "$HDL/common/queues/fifo.sv" "$HDL/common/queues/queue_stream.sv" "$TEST_DIR/ip_stubs.sv" \
    "$HDL/network/rdma/rdma_meta_tx_arbiter.sv" "$HDL/network/rdma/rdma_meta_rx_arbiter.sv" \
    "$TEST_DIR/tb_rdma_meta_arbiters.sv" > xvlog.log 2>&1 || { grep ERROR xvlog.log; exit 1; }
xelab -timescale 1ns/1ps tb -s tb > xelab.log 2>&1 || { grep ERROR xelab.log; exit 1; }
xsim tb -R > xsim.log 2>&1 || true
grep -E '^TB|Fatal' xsim.log
grep -q '^TB PASS' xsim.log
