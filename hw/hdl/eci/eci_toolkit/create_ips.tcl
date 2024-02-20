#   Copyright (c) 2022 ETH Zurich.
#   All rights reserved.
#
#   This file is distributed under the terms in the attached LICENSE file.
#   If you do not find this file, copies can be found by writing to:
#   ETH Zurich D-INFK, Stampfenbachstrasse 114, CH-8092 Zurich. Attn: Systems Group

puts "Regenerate ECI Toolkit IPs..."

# Debug bridge
create_ip -name debug_bridge -vendor xilinx.com -library ip \
              -module_name debug_bridge_dynamic
set_property -dict [list \
    CONFIG.C_DEBUG_MODE {1} \
    CONFIG.C_DESIGN_TYPE {1} \
    CONFIG.C_NUM_BS_MASTER {1} \
    ] [get_ips debug_bridge_dynamic]
generate_target all [get_ips debug_bridge_dynamic]

# Create ECI channel ILAs
create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_1
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {5} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_1]
generate_target all [get_ips ila_eci_channels_1]

create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_2
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {10} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {3} \
    CONFIG.C_PROBE7_WIDTH {4} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_2]
generate_target all [get_ips ila_eci_channels_2]

create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_3
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {15} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {3} \
    CONFIG.C_PROBE7_WIDTH {4} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE11_WIDTH {3} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_3]
generate_target all [get_ips ila_eci_channels_3]

create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_4
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {20} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {3} \
    CONFIG.C_PROBE7_WIDTH {4} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE11_WIDTH {3} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {64} \
    CONFIG.C_PROBE16_WIDTH {3} \
    CONFIG.C_PROBE17_WIDTH {4} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_4]
generate_target all [get_ips ila_eci_channels_4]

create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_5
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {25} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {3} \
    CONFIG.C_PROBE7_WIDTH {4} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE11_WIDTH {3} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {64} \
    CONFIG.C_PROBE16_WIDTH {3} \
    CONFIG.C_PROBE17_WIDTH {4} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE21_WIDTH {3} \
    CONFIG.C_PROBE22_WIDTH {4} \
    CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_5]
generate_target all [get_ips ila_eci_channels_5]

create_ip -name ila -vendor xilinx.com -library ip \
              -module_name ila_eci_channels_6
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {30} \
    CONFIG.C_DATA_DEPTH {1024} \
    CONFIG.C_EN_STRG_QUAL {0} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.C_PROBE0_WIDTH {64} \
    CONFIG.C_PROBE1_WIDTH {3} \
    CONFIG.C_PROBE2_WIDTH {4} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {64} \
    CONFIG.C_PROBE6_WIDTH {3} \
    CONFIG.C_PROBE7_WIDTH {4} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {1} \
    CONFIG.C_PROBE10_WIDTH {64} \
    CONFIG.C_PROBE11_WIDTH {3} \
    CONFIG.C_PROBE12_WIDTH {4} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {64} \
    CONFIG.C_PROBE16_WIDTH {3} \
    CONFIG.C_PROBE17_WIDTH {4} \
    CONFIG.C_PROBE18_WIDTH {1} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE21_WIDTH {3} \
    CONFIG.C_PROBE22_WIDTH {4} \
    CONFIG.C_PROBE23_WIDTH {1} \
    CONFIG.C_PROBE24_WIDTH {1} \
    CONFIG.C_PROBE25_WIDTH {64} \
    CONFIG.C_PROBE26_WIDTH {3} \
    CONFIG.C_PROBE27_WIDTH {4} \
    CONFIG.C_PROBE28_WIDTH {1} \
    CONFIG.C_PROBE29_WIDTH {1} \
    CONFIG.ALL_PROBE_SAME_MU {false} \
    ] [get_ips ila_eci_channels_6]
generate_target all [get_ips ila_eci_channels_6]
