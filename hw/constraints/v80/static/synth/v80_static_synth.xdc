# PCIe
create_clock -period 10.000 [get_ports pcie_clk_clk_p];

# DCMAC clocks
create_clock -period 3.103 -name gt0_refclk_p [get_ports gt0_refclk_p];

# PL-connected NVMe PCIe reference clock
create_clock -period 10.000 -name pl_nvme_refclk_p [get_ports pl_nvme_refclk_p];
