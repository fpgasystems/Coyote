# Script to set up IP and MAC address environment variables and insert the driver because environment is not initialized when executing through ssh from a remote server (environment is only initialized when MOTD is shown). 

CLI_PATH=/opt/hdev/cli

IP_address=$($CLI_PATH/hdev get network -d 1 | awk '$1 == "1:" {print $2}')
MAC_address=$($CLI_PATH/hdev get network -d 1 | awk '$1 == "1:" {print $3}' | tr -d '()')
qsfp_ip=$($CLI_PATH/common/address_to_hex IP $IP_address)
qsfp_mac=$($CLI_PATH/common/address_to_hex MAC $MAC_address)
echo "** IP_ADDRESS: $qsfp_ip"
echo "** MAC_ADDRESS: $qsfp_mac"

sudo insmod coyote_drv.ko ip_addr=$qsfp_ip mac_addr=$qsfp_mac