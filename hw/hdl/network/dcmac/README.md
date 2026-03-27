Utility modules for DCMAC integration in Coyote, including:
- A reset controller, which triggers the reset sequence of the GT transceivers, the DCMAC (core, serdes and channel) and AXIS infrastructure
- Clock utility modules, which map a single input clock to a bus of clocks of the same frequency
- An AXI Stream to Segmented AXI Stream converter for the DCMAC TX path
- A Segmented AXI Stream to AXI Stream converter for the DCMAC RX path (note, originally developed by AMD and open-sourced in SLASH: https://github.com/Xilinx/SLASH)
- A module setting "magic" DCMAC values for 200G operation (note, originally developed by AMD and open-sourced in SLASH: https://github.com/Xilinx/SLASH)