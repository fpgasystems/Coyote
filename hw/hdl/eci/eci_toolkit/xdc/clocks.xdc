# Fabric clocks

create_clock -period 3.103 -name clk_sys -waveform {0.000 1.552} [get_ports clk_sys]
create_clock -period 50.000 -name s_bscan_tck -waveform {0.000 25.000} [get_ports s_bscan_tck]

create_clock -period 10.000 -name clk_io -waveform {0.000 5.000} [get_ports prgc0_clk_p]
create_clock -period 3.333 -name clk_prgc1 -waveform {0.000 1.667} [get_ports prgc1_clk_p]

create_clock -period 3.103 -name F_MAC0C_CLK_P [get_ports F_MAC0C_CLK_P]
create_clock -period 3.103 -name F_MAC1C_CLK_P [get_ports F_MAC1C_CLK_P]
create_clock -period 3.103 -name F_MAC2C_CLK_P [get_ports F_MAC2C_CLK_P]
create_clock -period 3.103 -name F_MAC3C_CLK_P [get_ports F_MAC3C_CLK_P]

create_clock -period 10.000 -name F_NVMEC_CLK_P [get_ports F_NVMEC_CLK_P]

create_clock -period 10.000 -name F_PCIE16C_CLK_P [get_ports F_PCIE16C_CLK_P]
