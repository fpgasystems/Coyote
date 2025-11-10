#!/bin/bash

######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

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
