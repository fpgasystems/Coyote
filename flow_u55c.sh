#!/bin/bash

BASE_DIR="/mnt/scratch/linvogel/coyote"

echo "Enter build directory relative to $BASE_DIR:"
read BUILD_DIR

# parameters
# FPGA_BIT_PATH=/local/home/zhe/coyote/bft-coyote-gitlab-master/hw/bitstream/top_new_tcp_intf_5 #bitstream used mostly before pcie_rx batching
FPGA_BIT_PATH=$BASE_DIR/$BUILD_DIR/bitstreams/cyt_top #bitstream with pcie ex batching
DRIVER_PATH=$BASE_DIR/driver/
DRIVER_REMOTE_PATH=$BASE_DIR/driver/
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )


# server IDs (u55c)
echo "Enter u55c server ids (space separated):"
read -a SERVID

echo "Running in $BUILD_DIR for servers ${SERVID[@]}"

# args
PROGRAM_FPGA=$1
HOT_RESET=$2

alveo_program()
{
	SERVERADDR=$1
	SERVERPORT=$2
	BOARDSN=$3
	DEVICENAME=$4
	BITPATH=$5
	vivado -nolog -nojournal -mode batch -source $SCRIPT_DIR/program_alveo.tcl -tclargs $SERVERADDR $SERVERPORT $BOARDSN $DEVICENAME $BITPATH
}

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 program_fpga<0/1> reboot_host<0/1>" >&2
  exit 1
fi

if ! [ -x "$(command -v vivado)" ]; then
	echo "Vivado does NOT exist in the system."
	exit 1
fi

# generate host name list
BOARDSN=(XFL1QOQ1ATTYA XFL1O5FZSJEIA XFL1QGKZZ0HVA XFL11JYUKD4IA XFL1EN2C02C0A XFL1NMVTYXR4A XFL1WI3AMW4IA XFL1ELZXN2EGA XFL1W5OWZCXXA XFL1H2WA3T53A)
for servid in ${SERVID[@]}; do 
	# hostlist+="alveo-u55c-$(printf "%02d" $servid).ethz.ch "
	hostlist+="alveo-u55c-$(printf "%02d" $servid) "
done

# STEP1: Program FPGA
if [ $PROGRAM_FPGA -eq 1 ]; then
	# activate servers (login with passwd to enable the nfs home mounting)
	echo "Activating server..."
	#parallel-ssh -H "$hostlist" -A -O PreferredAuthentications=password "echo Login success!"
	parallel-ssh -H "$hostlist" "echo Login success!"
	# enable hardware server
	echo "Enabling Vivado hw_server..."
	# this step will be timeout after 2 secs to avoid the shell blocking
	parallel-ssh -H "$hostlist" -t 2 "source /tools/Xilinx/Vivado/2022.1/settings64.sh && hw_server &"
	echo "Programming FPGA...$FPGA_BIT_PATH"
	for servid in "${SERVID[@]}"; do
		boardidx=$(expr $servid - 1)
		# alveo_program alveo-u55c-$(printf "%02d" $servid).ethz.ch 3121 ${BOARDSN[boardidx]} xcu280_u55c_0 $FPGA_BIT_PATH &
		alveo_program alveo-u55c-$(printf "%02d" $servid) 3121 ${BOARDSN[boardidx]} xcu280_u55c_0 $FPGA_BIT_PATH &

	done
	wait
	# read -p "FPGA programmed. Press enter to continue or Ctrl-C to exit."
	echo "FPGA programmed...$FPGA_BIT_PATH"
fi

# STEP2: Reboot Host (FIXME: change to hot reset)
if [ $HOT_RESET -eq 1 ]; then
	#NOTE: put -x '-tt' (pseudo terminal) here for sudo command
	echo "Removing the driver..."
	parallel-ssh -H "$hostlist" -x '-tt' "sudo rmmod coyote_drv"
	echo "Hot resetting PCIe..."	
	parallel-ssh -H "$hostlist" -x '-tt' 'sudo /opt/cli/program/pci_hot_plug "$(hostname -s)"'
	echo "Hot-reset done."	
	# read -p "Hot-reset done. Press enter to load the driver or Ctrl-C to exit."
	echo "Copy Coyote driver (skipped because this is the same scratch folder)"
	# parallel-scp -H "$hostlist" -r $DRIVER_PATH $DRIVER_REMOTE_PATH
	echo "Compile Coyote driver"
	parallel-ssh -H "$hostlist" "make -C $DRIVER_REMOTE_PATH"
	echo "Loading driver..."
	parallel-ssh -H "$hostlist" -x '-tt' "sudo insmod $DRIVER_REMOTE_PATH/coyote_drv.ko && sudo /opt/cli/program/fpga_chmod 0"
	echo "Driver loaded."
fi

# # STEP3: Upload host bin
# if [ $UPDATE_HOSTBIN -eq 1 ]; then
# 	echo "Copying program to Workspace"
# 	cp -r $HOSTBIN_PATH $HOSTBIN_REMOTE_PATH 
# 	# parallel-scp -H "$hostlist" $HOSTBIN_PATH $HOSTBIN_REMOTE_PATH
# fi

#TODO: STEP4: Run host bin

exit 0
