# Minimal dummy ILA - satisfies debug_bridge_user Chipscope DRC (16-320).
# Without an ILA, open_checkpoint fires a non-downgradable ERROR because
# debug_bridge_user (unconditionally instantiated) has no connected clock.
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_dummy
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_dummy
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}
set_property -dict [list CONFIG.C_NUM_OF_PROBES {1}] [get_ips ila_dummy]
