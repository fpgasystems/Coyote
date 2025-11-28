#!/usr/bin/env bash
# Usage:
#   ./launch_with_numa_bound.sh <DEVICE_ID> <command> [args...]


### A utility script to launch a host program bound to the same numa node of the target Coyote FPGA device
set -euo pipefail

command -v hdev >/dev/null 2>&1 || {
    echo "Error: 'hdev' command not found. Install or add it to PATH." >&2
    exit 1
}

command -v numactl >/dev/null 2>&1 || {
    echo "Error: 'numactl' is not installed. Install numactl package." >&2
    exit 1
}

command -v lscpu >/dev/null 2>&1 || {
    echo "Error: 'lscpu' not found. Install util-linux package." >&2
    exit 1
}



if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <DEVICE_ID> <command> [args...]"
    exit 1
fi

DEVICE_ID="$1"
shift

# ---- Step 1: Query hdev and get the BDF for this device ID ----
BDF_LINE=$(hdev get bdf | awk -v id="$DEVICE_ID" '$1 == id ":" {print $2}')

if [ -z "$BDF_LINE" ]; then
    echo "Error: No BDF found for device ID ${DEVICE_ID}"
    exit 1
fi

BDF="$BDF_LINE"

# Add domain prefix if missing
if [[ ! "$BDF" =~ ^[0-9a-fA-F]{4}: ]]; then
    PCI_ADDR="0000:${BDF}"
else
    PCI_ADDR="$BDF"
fi

echo "Device ID ${DEVICE_ID} → PCI address ${PCI_ADDR}"

SYS_PATH="/sys/bus/pci/devices/${PCI_ADDR}"

if [ ! -d "$SYS_PATH" ]; then
    echo "Error: PCI device ${PCI_ADDR} not found in sysfs at ${SYS_PATH}"
    exit 1
fi

NUMA_NODE=$(cat "${SYS_PATH}/numa_node")

if [ "$NUMA_NODE" -lt 0 ]; then
    echo "Warning: NUMA node is -1. Falling back to node 0"
    NUMA_NODE=0
fi

echo "NUMA node: ${NUMA_NODE}"

CPUS=$(lscpu -p=CPU,NODE | grep -v '^#' | \
       awk -F, -v node="$NUMA_NODE" '$2 == node {cpus = (cpus ? cpus "," $1 : $1)} END {print cpus}')

if [ -z "$CPUS" ]; then
    echo "Error: No CPUs found for NUMA node ${NUMA_NODE}"
    exit 1
fi

#echo "CPUs on NUMA node ${NUMA_NODE}: ${CPUS}"

# ---- Step 4: Launch the command pinned to this NUMA node ----
echo "Running on NUMA node ${NUMA_NODE}: $*"

exec numactl --cpunodebind="${NUMA_NODE}" --membind="${NUMA_NODE}" "$@"