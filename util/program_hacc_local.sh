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

BIT_PATH=$1
DRV_PATH=$2
if [ -z "$3" ]; then
    DEVICE=1
else
    DEVICE=$3
fi

# Bitstream loading
echo "** Programming the FPGA with $BIT_PATH"
hdev program vivado -b $BIT_PATH -d $DEVICE
echo " "

# Driver insertion
echo "** Inserting the driver from $DRV_PATH"
echo "** IP_ADDRESS: $DEVICE_1_IP_ADDRESS_HEX_0"
echo "** MAC_ADDRESS: $DEVICE_1_MAC_ADDRESS_0"
echo "y" | hdev program driver -i $DRV_PATH -p ip_addr=$DEVICE_1_IP_ADDRESS_HEX_0,mac_addr=$DEVICE_1_MAC_ADDRESS_0
echo " "

# Final greetings
echo "** It's Coyote after all, so thoughts & prayers!"
echo "** Lasciate ogni speranza, voi ch'entrate - Ihr, die ihr hier eintretet, lasst alle Hoffnung fahren"
