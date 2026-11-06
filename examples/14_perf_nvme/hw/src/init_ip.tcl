# NOTE: On Versal architecture, the IP is called axis_ila instead of ila
if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    create_ip -name ila -vendor xilinx.com -library ip -module_name ila_perf_nvme
} elseif {$cfg(fpga_arch) eq "versal"} {
    create_ip -name axis_ila -vendor xilinx.com -library ip -module_name ila_perf_nvme
} else {
    puts "ERROR: Unsupported FPGA architecture: $cfg(fpga_arch)"
    exit 1
}

set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {16} \
    CONFIG.C_EN_STRG_QUAL {1} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {4} \
    CONFIG.C_DATA_DEPTH {8192} \
    CONFIG.C_PROBE0_WIDTH  {8}  \
    CONFIG.C_PROBE1_WIDTH  {2}  \
    CONFIG.C_PROBE2_WIDTH  {32} \
    CONFIG.C_PROBE3_WIDTH  {32} \
    CONFIG.C_PROBE4_WIDTH  {1}  \
    CONFIG.C_PROBE5_WIDTH  {2}  \
    CONFIG.C_PROBE6_WIDTH  {1}  \
    CONFIG.C_PROBE7_WIDTH  {1}  \
    CONFIG.C_PROBE8_WIDTH  {1}  \
    CONFIG.C_PROBE9_WIDTH  {4}  \
    CONFIG.C_PROBE10_WIDTH {32} \
    CONFIG.C_PROBE11_WIDTH {16} \
    CONFIG.C_PROBE12_WIDTH {1}  \
    CONFIG.C_PROBE13_WIDTH {16} \
    CONFIG.C_PROBE14_WIDTH {4}  \
    CONFIG.C_PROBE15_WIDTH {1}  \
] [get_ips ila_perf_nvme]
