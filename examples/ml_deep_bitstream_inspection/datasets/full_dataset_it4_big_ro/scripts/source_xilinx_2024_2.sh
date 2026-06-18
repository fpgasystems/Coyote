#!/usr/bin/env bash
# Source Xilinx 2024.2 tools for Coyote hardware builds.

set -euo pipefail

source /tools/Xilinx/Vivado/2024.2/settings64.sh
source /tools/Xilinx/Vitis/2024.2/settings64.sh
source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh

echo "[tools] vivado=$(command -v vivado)"
echo "[tools] vitis=$(command -v vitis || true)"
echo "[tools] vitis_hls=$(command -v vitis_hls)"
