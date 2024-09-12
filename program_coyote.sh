## 
## Read in the arguments for programming the FPGA 
## 

# Required arguments: Bitstream-path, driver-path and qsfp-port (assigned automatically if not provided)
if [ "$1" == "-h" ]; then
  echo "Usage: $0 <bitstream_path_within_base> <driver_path_within_base> <qsfp_port>" >&2
  exit 0
fi

if ! [ -x "$(command -v vivado)" ]; then
	echo "Vivado does NOT exist in the system."
	exit 1
fi

# Get the current basepath of the script 
BASE_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Set relevant parameters for FPGA-programming 
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
## Program the FPGA via the sgutil call - only work locally for the server that you are currently logged in to
##

if [ $PROGRAM_FPGA -eq 1 ]; then
    echo "***"
    echo "** Programming the FPGA with $BIT_PATH"
    echo "***"
    sgutil program vivado -b $BIT_PATH
    echo "***"
    echo "** FPGA programmed"
    echo "***"
fi
echo " "
echo " "

##
## Insert the driver for the FPGA with the required IP- and MAC-Address
## 

if [ $DRV_INSERT -eq 1 ]; then 
    echo "***"
    echo "** Inserting the driver from $DRV_PATH"
    echo "***"
    echo "** IP_ADDRESS: $DEVICE_1_IP_ADDRESS_HEX_0"
    echo "** MAC_ADDRESS: $DEVICE_1_MAC_ADDRESS_0"
    sgutil program driver -m $DRV_PATH -p ip_addr=$DEVICE_1_IP_ADDRESS_HEX_0,mac_addr=$DEVICE_1_MAC_ADDRESS_0
    # sgutil program driver -m $DRV_PATH
    echo "***"
    echo "** Driver loaded "
    echo "***"
fi 
echo " "
echo " "

##
## Final greetings 
## 

echo "***"
echo "** It's Coyote after all, so thoughts & prayers!"
echo "** Lasciate ogni speranza, voi ch'entrate - Ihr, die ihr hier eintretet, lasst alle Hoffnung fahren"
echo "***"

