#!/usr/bin/env bash
# Install what the container needs: Verilator, the Verilator testbench of one example (sim/vl/configure.sh,
# no Vivado) and its host program, built against the simulation library. Runs as root in Ubuntu 22.04
# (Dockerfile and coyote-sim.def call it); it also works on a plain Ubuntu machine without Vivado.
#
# Usage: install.sh <coyote checkout> <example hw dir> <work dir> <example sw dir>
#        install.sh --deps
#   <example hw dir>  for example <coyote>/examples/01_hello_world/hw
#   <work dir>        the build folder to create (COYOTE_SIM_DIR at run time)
#   <example sw dir>  for example <coyote>/examples/01_hello_world/sw
#   --deps            only the packages and Verilator; the Dockerfile runs this in a layer of its own,
#                     before the checkout is copied, so an edit to the checkout does not rebuild Verilator
set -euo pipefail

HERE=$(dirname "$(realpath "$0")")
PREFIX=${PREFIX:-/opt/verilator}

install_deps() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates python3 python3-jinja2 tcl \
        autoconf flex bison help2man perl ccache libfl2 libfl-dev zlib1g-dev \
        libboost-all-dev
    rm -rf /var/lib/apt/lists/*
    # The pinned Verilator (sim/vl/verilator.env); the clone and the objects are not needed afterwards.
    "$HERE/../vl/install_verilator.sh" "$PREFIX"
    rm -rf "$(dirname "$PREFIX")/src/verilator"
}

if [ "${1:-}" = "--deps" ]; then
    install_deps
    exit 0
fi
if [ $# -ne 4 ]; then
    echo "usage: $0 <coyote checkout> <example hw dir> <work dir> <example sw dir>  |  $0 --deps" >&2
    exit 1
fi
COYOTE=$(realpath "$1")
HW=$(realpath "$2")
WORK=$3
SW=$(realpath "$4")

[ -x "$PREFIX/bin/verilator" ] || install_deps
export PATH=$PREFIX/bin:$PATH

# The Python tests of an example are in sim/unit_test/examples/<example folder>, if it has any.
"$COYOTE/sim/vl/configure.sh" "$HW" "$WORK" -DFDEV_NAME=u55c \
    -DUNIT_TEST_DIR="$COYOTE/sim/unit_test/examples/$(basename "$(dirname "$HW")")"
"$COYOTE/sim/vl/build.sh" "$WORK" "$WORK/vl_cpp"

cmake -S "$SW" -B "$WORK/sw" -DEN_SIM=ON
cmake --build "$WORK/sw" -j "$(nproc)"
echo "installed: $PREFIX/bin/verilator, $WORK/vl_cpp/coyote_vl, $WORK/sw/test"
