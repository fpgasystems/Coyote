#!/bin/bash

### A utility script to program a remote FPGA with a Coyote bitstream and insert the driver on the ETHZ HACC cluster
### This script can be executed from any node and it will program the specified alveo-u55c node(s)
### NOTE: This script must be executed from the Coyote/util directory

#  Arguments: bistream path, driver path and device ID (optional)
if [ "$1" == "-h" ]; then
  echo "Usage: $0 <bitstream_path_within_base> <driver_path_within_base> <device>" >&2
  exit 0
fi

BITSTREAM_PATH=$1
DRIVER_PATH=$2
if [ -z "$3" ]; then
  DEVICE=1
else
  DEVICE=$3
fi

# Ask user for the FPGAs to be programmed
echo "*** Enter space-separated U55C server IDs:"
read -a SERVID

# Program each node using parallel-ssh and the local script
BASE_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
for servid in ${SERVID[@]}; do 
	hostlist+="alveo-u55c-$(printf "%02d" $servid) "
done

echo "** Checking nodes..."
parallel-ssh -H "$hostlist" "echo ** Login success!"
parallel-ssh -P -v -H "$hostlist" "source /tools/Xilinx/Vivado/2024.2/settings64.sh && cd $BASE_PATH && source program_hacc_local.sh $BITSTREAM_PATH $DRIVER_PATH $DEVICE"
