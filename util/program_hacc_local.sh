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

### A utility script to program a local FPGA with a Coyote bitstream and insert the driver on the ETHZ HACC cluster
### This script should be executed from the node where the FPGA is (e.g., alveo-u55c-05, alveo-box-01, etc.) and from the Coyote/util directory

# Check Vivado is available
 if ! [ -x "$(command -v vivado)" ]; then
 	echo "Vivado not found. Please make sure Vivado is installed."
 	exit 1
fi

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

# Environment set-up --- get IP and MAC address of the FPGA; convert to hex
CLI_PATH=/opt/hdev/cli
IP_ADDRESS=$($CLI_PATH/hdev get network -d 1 | awk '$1 == "1:" {print $2}')
MAC_ADDRESS=$($CLI_PATH/hdev get network -d 1 | awk '$1 == "1:" {print $3}' | tr -d '()')
IP_HEX=$($CLI_PATH/common/address_to_hex IP $IP_ADDRESS)
MAC_HEX=$($CLI_PATH/common/address_to_hex MAC $MAC_ADDRESS)

# Bitstream loading
echo "** Programming the FPGA with $BITSTREAM_PATH"
$CLI_PATH/hdev program vivado -b $BITSTREAM_PATH -d $DEVICE
if [ $? -ne 0 ]; then
  echo "Error: Failed to program the FPGA with the bitstream."
  exit 1
fi

# Driver insertion
echo "** Inserting the driver from $DRIVER_PATH"
echo "** FPGA IP_ADDRESS: $IP_HEX"
echo "** FPGA MAC_ADDRESS: $MAC_HEX"
echo "y" | $CLI_PATH/hdev program driver -i $DRIVER_PATH -p ip_addr=$IP_HEX,mac_addr=$MAC_HEX
if [ $? -ne 0 ]; then
  echo "Error: Failed to insert Coyote driver."
  exit 1
fi

# Final greetings
echo "** It's Coyote after all, so thoughts & prayers!"
echo "** Lasciate ogni speranza, voi ch'entrate - Ihr, die ihr hier eintretet, lasst alle Hoffnung fahren"
