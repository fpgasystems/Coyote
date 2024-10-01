#!/bin/bash

##
## Args
##

if [ "$1" == "-h" ]; then
  echo "Usage: $0 <bitstream_path_within_base> <driver_path_within_base> <qsfp_port>" >&2
  exit 0
fi

if ! [ -x "$(command -v vivado)" ]; then
	echo "Vivado does NOT exist in the system."
	exit 1
fi

BASE_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

PROGRAM_FPGA=1
DRV_INSERT=1

BIT_PATH=$1
DRV_PATH=$2

if [ -z "$3" ]; then
    QSFP_PORT=0
else
    QSFP_PORT=$3
fi

##
## Server IDs (u55c)
##

echo "*** Enter server IDs:"
read -a SERVID

BOARDSN=(XFL1QOQ1ATTYA XFL1O5FZSJEIA XFL1QGKZZ0HVA XFL11JYUKD4IA XFL1EN2C02C0A XFL1NMVTYXR4A XFL1WI3AMW4IA XFL1ELZXN2EGA XFL1W5OWZCXXA XFL1H2WA3T53A)

for servid in ${SERVID[@]}; do 
	# hostlist+="alveo-u55c-$(printf "%02d" $servid).ethz.ch "
	hostlist+="alveo-u55c-$(printf "%02d" $servid) "
done

##
## Program FPGA
##

alveo_program()
{
	SERVERADDR=$1
	SERVERPORT=$2
	BOARDSN=$3
	DEVICENAME=$4
	BITPATH=$5
	vivado -nolog -nojournal -mode batch -source program_alveo.tcl -tclargs $SERVERADDR $SERVERPORT $BOARDSN $DEVICENAME $BITPATH
}

if [ $PROGRAM_FPGA -eq 1 ]; then
	# activate servers (login with passwd to enable the nfs home mounting)
	echo "*** Activating server ..."
    echo " ** "
        #parallel-ssh -H "$hostlist" -A -O PreferredAuthentications=password "echo Login success!"
        parallel-ssh -H "$hostlist" "echo Login success!"

	echo "*** Enabling Vivado hw_server ..."
    echo " ** "
        # this step will be timeout after 2 secs to avoid the shell blocking
        parallel-ssh -H "$hostlist" -t 8 "source /tools/Xilinx/Vivado/2022.1/settings64.sh && hw_server &"

	echo "*** Programming FPGA... (path: $BIT_PATH)"
    echo " ** "
        for servid in "${SERVID[@]}"; do
            boardidx=$(expr $servid - 1)
            alveo_program alveo-u55c-$(printf "%02d" $servid) 3121 ${BOARDSN[boardidx]} xcu280_u55c_0 $BASE_PATH/../$BIT_PATH &
        done
	    wait
	
    echo "*** FPGA programmed"
    echo " ** "
fi

##
## Driver insertion
##
if [ $DRV_INSERT -eq 1 ]; then
	#NOTE: put -x '-tt' (pseudo terminal) here for sudo command
	echo "*** Removing the driver ..."
    echo " ** "
	    parallel-ssh -H "$hostlist" -x '-tt' "sudo rmmod coyote_drv"
	
    echo "*** Rescan PCIe ..."	
    echo " ** "
	    #parallel-ssh -H "$hostlist" -x '-tt' 'sudo /opt/sgrt/cli/program/pci_hot_plug "$(hostname -s)"'
	    parallel-ssh -H "$hostlist" -x '-tt' 'upstream_port=$(/opt/sgrt/cli/get/get_fpga_device_param 1 upstream_port) && root_port=$(/opt/sgrt/cli/get/get_fpga_device_param 1 root_port) && LinkCtl=$(/opt/sgrt/cli/get/get_fpga_device_param 1 LinkCtl) && sudo /opt/sgrt/cli/program/pci_hot_plug 1 $upstream_port $root_port $LinkCtl'
	    # read -p "Hot-reset done. Press enter to load the driver or Ctrl-C to exit."

    echo "*** Compiling the driver ..."
    echo " ** "
	    parallel-ssh -H "$hostlist" "make -C $BASE_PATH/../$DRV_PATH"
	
    echo "*** Loading the driver ..."
    echo " ** "
        qsfp_ip="DEVICE_1_IP_ADDRESS_HEX_$QSFP_PORT"
        qsfp_mac="DEVICE_1_MAC_ADDRESS_$QSFP_PORT"

	    parallel-ssh -H "$hostlist" -x '-tt' "sudo insmod $BASE_PATH/../$DRV_PATH/coyote_drv.ko ip_addr=\$$qsfp_ip mac_addr=\$$qsfp_mac"

    echo "*** Driver loaded"
    echo " ** "
fi


