#!/bin/bash 

# activate the nfs home folder via passwd ssh, enable the pub key
act_sshpass()
{
	SERVERADDR=$1
	PASS=$2
	echo "Activating server $1"
	sshpass -p "$PASS" ssh runshi@$SERVERADDR "echo Success!"
}

alveo_program()
{
	SERVERADDR=$1
	SERVERPORT=$2
	BOARDSN=$3
	DEVICENAME=$4
	BITPATH=$5
	vivado -nolog -nojournal -mode batch -source program_alveo.tcl -tclargs ${SERVERADDR} ${SERVERPORT} ${BOARDSN} ${DEVICENAME} ${BITPATH}
}


if [ "$#" -ne 4 ]; then
  echo "Usage: $0 program_fpga<0/1> reboot_host<0/1> update_hostbin<0/1> run_hostbin<0/1>" >&2
  exit 1
fi

# Parameters
ALVEOPASS=OpenR1sc1102

# Parameters
FPGABITPATH=/home/runshi/Workspace/hw/coyote_dev/hw/build7/lynx/lynx.runs/impl_1/top
DRIVER=/home/runshi/Workspace/hw/coyote_dev/driver/fpga_drv.ko
HOSTBIN=/home/runshi/Workspace/hw/coyote_dev/sw/examples/tm/build/main
REMOTEDIR=/home/runshi/
PROGRAM_FPGA=$1
REBOOT_HOST=$2
UPDATE_HOSTBIN=$3
RUN_HOSTBIN=$4

if [ $PROGRAM_FPGA -eq 1 ]; then
	# activate servers
	echo "Activating server"
	act_sshpass alveo3b.ethz.ch $ALVEOPASS
	act_sshpass alveo3c.ethz.ch $ALVEOPASS
	# enable hardware server
	echo "Enabling hw_server on remote"
	pssh -h hosts_alveo.txt "/opt/tools/Xilinx/Vivado/2020.1/bin/loader -exec hw_server &"
	# may hang if the hw_server is NOT on. Ctrl-C to interrupt pssh and continue
	echo "Programming FPGA..."
	alveo_program alveo3b.ethz.ch 3121 21770213S01PA xcu280_0 $FPGABITPATH
	alveo_program alveo3c.ethz.ch 3121 21770297400DA xcu280_0 $FPGABITPATH
	# alveo_program alveo-u55c-04.ethz.ch 3121 XFL11JYUKD4IA xcu280_u55c_0 $FPGABITPATH
	# alveo_program alveo-u55c-05.ethz.ch 3121 XFL1EN2C02C0A xcu280_u55c_0 $FPGABITPATH

	read -p "Program FPGA is done. Press enter to continue after manually reboot"
fi

if [ $REBOOT_HOST -eq 1 ]; then
	read -p "Confirm the server is rebooted"
	act_sshpass alveo3b.ethz.ch $ALVEOPASS
	act_sshpass alveo3c.ethz.ch $ALVEOPASS	
	echo "Enable hw_server"	
	# pssh -h hosts_alveo.txt "/opt/tools/Xilinx/Vivado/2020.1/bin/loader -exec hw_server &"
	echo "Load coyote driver"
	pssh -h hosts_alveo.txt "cp ~/Workspace/coyote_dev/driver/fpga_drv.ko /tmp/fpga_drv.ko"
	pssh -i -h hosts_alveo.txt "sudo insmod /tmp/fpga_drv.ko && sudo /mnt/scratch/src/get_fpga.sh 0"
	echo "Load driver success"
fi

# upload host binary
if [ $UPDATE_HOSTBIN -eq 1 ]; then
	echo "Copying program to hosts"
	pscp -h hosts_alveo.txt $HOSTBIN $REMOTEDIR
fi






























exit 0