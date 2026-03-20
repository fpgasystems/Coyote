# NOTE: On Versal architecture, the IP is called axis_ila instead of ila
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_vfpga_interrupt
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_vfpga_interrupt
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}
set_property -dict [list CONFIG.C_NUM_OF_PROBES {6} CONFIG.C_PROBE5_WIDTH {512} CONFIG.C_PROBE1_WIDTH {32} CONFIG.C_EN_STRG_QUAL {1} CONFIG.C_PROBE5_MU_CNT {2} CONFIG.C_PROBE4_MU_CNT {2} CONFIG.C_PROBE3_MU_CNT {2} CONFIG.C_PROBE2_MU_CNT {2} CONFIG.C_PROBE1_MU_CNT {2} CONFIG.C_PROBE0_MU_CNT {2} CONFIG.ALL_PROBE_SAME_MU_CNT {2}] [get_ips ila_vfpga_interrupt]
