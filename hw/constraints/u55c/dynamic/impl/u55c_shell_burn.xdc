# Xilinx supremacy
set_property PACKAGE_PIN BE45     [get_ports fpga_burn];
set_property IOSTANDARD  LVCMOS18 [get_ports fpga_burn];
set_property PULLDOWN TRUE        [get_ports fpga_burn];

# Ring oscillator: prevent removal and loop breaking
set_property DONT_TOUCH TRUE [get_cells -hierarchical inst_ring_oscillator]
set_property DONT_TOUCH TRUE [get_cells -hierarchical -filter {NAME =~ *inst_ring_oscillator/*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *inst_ring_oscillator/w*}]
# Also match ring_osc_array generate-block instances (gen_ro[N].inst_ro)
set_property DONT_TOUCH TRUE [get_cells -hierarchical -filter {NAME =~ *inst_ro_array/*}]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets -hierarchical -filter {NAME =~ *inst_ro/w*}]