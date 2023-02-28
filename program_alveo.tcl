
set serveraddr  [lindex $::argv 0]
set serverport [lindex $::argv 1]
set boardsn [lindex $::argv 2]
set devicename  [lindex $::argv 3]
set bitpath [lindex $::argv 4]

open_hw_manager

set_param labtools.enable_cs_server false

connect_hw_server -url ${serveraddr}:${serverport} -allow_non_jtag
current_hw_target [get_hw_targets */xilinx_tcf/Xilinx/${boardsn}]
set_property PARAM.FREQUENCY 15000000 [get_hw_targets */xilinx_tcf/Xilinx/${boardsn}]
open_hw_target

current_hw_device [get_hw_devices ${devicename}]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices ${devicename}] 0]

set_property PROGRAM.FILE ${bitpath}.bit [get_hw_devices ${devicename}]
# check if probes file exists
if { [file exists ${bitpath}.ltx] == 1} {
	set_property PROBES.FILE ${bitpath}.ltx [get_hw_devices ${devicename}]
	set_property FULL_PROBES.FILE ${bitpath}.ltx [get_hw_devices ${devicename}]
	#puts "INFO: ILA probes .ltx found."
}

program_hw_devices [get_hw_devices ${devicename}]
refresh_hw_device [lindex [get_hw_devices ${devicename}] 0]

# close target or setup ILA trigger
close_hw_target ${serveraddr}:${serverport}/xilinx_tcf/Xilinx/${boardsn}
close_hw_manager

