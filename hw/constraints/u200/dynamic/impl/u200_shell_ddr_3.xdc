# DDR clocks
set_property	PACKAGE_PIN	H16		            [get_ports 	c3_sys_clk_n] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c3_sys_clk_n] ; 
set_property	PACKAGE_PIN	J16		            [get_ports 	c3_sys_clk_p] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c3_sys_clk_p] ; 

####
### DDR4 c3
####

set_property -dict {PACKAGE_PIN B24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[34]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ34"      - IO_L23N_T3U_N9_72
set_property -dict {PACKAGE_PIN B25  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[35]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ35"      - IO_L23P_T3U_N8_72
set_property -dict {PACKAGE_PIN A24  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[8] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C4"    - IO_L22N_T3U_N7_DBC_AD0N_72
set_property -dict {PACKAGE_PIN A25  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[8] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T4"    - IO_L22P_T3U_N6_DBC_AD0P_72
set_property -dict {PACKAGE_PIN A22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[33]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ33"      - IO_L24N_T3U_N11_72
set_property -dict {PACKAGE_PIN A23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[32]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ32"      - IO_L24P_T3U_N10_72
set_property -dict {PACKAGE_PIN C23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[39]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ39"      - IO_L21N_T3L_N5_AD8N_72
set_property -dict {PACKAGE_PIN C24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[38]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ38"      - IO_L21P_T3L_N4_AD8P_72
set_property -dict {PACKAGE_PIN B22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[36]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ36"      - IO_L20N_T3L_N3_AD1N_72
set_property -dict {PACKAGE_PIN C22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[37]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ37"      - IO_L20P_T3L_N2_AD1P_72
set_property -dict {PACKAGE_PIN D23  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[9] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C13"   - IO_L19N_T3L_N1_DBC_AD9N_72
set_property -dict {PACKAGE_PIN D24  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[9] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T13"   - IO_L19P_T3L_N0_DBC_AD9P_72
set_property -dict {PACKAGE_PIN E22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[57]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ57"      - IO_L17N_T2U_N9_AD10N_72
set_property -dict {PACKAGE_PIN F22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[56]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ56"      - IO_L17P_T2U_N8_AD10P_72
set_property -dict {PACKAGE_PIN E23  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[14]]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C7"    - IO_L16N_T2U_N7_QBC_AD3N_72
set_property -dict {PACKAGE_PIN F23  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[14]]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T7"    - IO_L16P_T2U_N6_QBC_AD3P_72
set_property -dict {PACKAGE_PIN G21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[59]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ59"      - IO_L18N_T2U_N11_AD2N_72
set_property -dict {PACKAGE_PIN G22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[58]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ58"      - IO_L18P_T2U_N10_AD2P_72
set_property -dict {PACKAGE_PIN E25  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[61]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ61"      - IO_L15N_T2L_N5_AD11N_72
set_property -dict {PACKAGE_PIN F25  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[62]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ62"      - IO_L15P_T2L_N4_AD11P_72
set_property -dict {PACKAGE_PIN F24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[60]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ60"      - IO_L14N_T2L_N3_GC_72
set_property -dict {PACKAGE_PIN G25  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[63]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ63"      - IO_L14P_T2L_N2_GC_72
set_property -dict {PACKAGE_PIN H22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[15]]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C16"   - IO_L13N_T2L_N1_GC_QBC_72
set_property -dict {PACKAGE_PIN H23  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[15]]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T16"   - IO_L13P_T2L_N0_GC_QBC_72
set_property -dict {PACKAGE_PIN J23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[9]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ9"       - IO_L11N_T1U_N9_GC_72
set_property -dict {PACKAGE_PIN J24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[8]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ8"       - IO_L11P_T1U_N8_GC_72
set_property -dict {PACKAGE_PIN H21  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[2] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C1"    - IO_L10N_T1U_N7_QBC_AD4N_72
set_property -dict {PACKAGE_PIN J21  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[2] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T1"    - IO_L10P_T1U_N6_QBC_AD4P_72
set_property -dict {PACKAGE_PIN G24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[11]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ11"      - IO_L12N_T1U_N11_GC_72
set_property -dict {PACKAGE_PIN H24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[10]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ10"      - IO_L12P_T1U_N10_GC_72
set_property -dict {PACKAGE_PIN L23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[13]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ13"      - IO_L9N_T1L_N5_AD12N_72
set_property -dict {PACKAGE_PIN L24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[12]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ12"      - IO_L9P_T1L_N4_AD12P_72
set_property -dict {PACKAGE_PIN K21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[15]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ15"      - IO_L8N_T1L_N3_AD5N_72
set_property -dict {PACKAGE_PIN K22  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[14]   ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ14"      - IO_L8P_T1L_N2_AD5P_72
set_property -dict {PACKAGE_PIN L22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[3] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C10"   - IO_L7N_T1L_N1_QBC_AD13N_72
set_property -dict {PACKAGE_PIN M22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[3] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T10"   - IO_L7P_T1L_N0_QBC_AD13P_72
set_property -dict {PACKAGE_PIN N24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[1]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ1"       - IO_L5N_T0U_N9_AD14N_72
set_property -dict {PACKAGE_PIN P24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[0]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ0"       - IO_L5P_T0U_N8_AD14P_72
set_property -dict {PACKAGE_PIN R22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[0] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C0"    - IO_L4N_T0U_N7_DBC_AD7N_72
set_property -dict {PACKAGE_PIN T22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[0] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T0"    - IO_L4P_T0U_N6_DBC_AD7P_72
set_property -dict {PACKAGE_PIN R23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[3]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ3"       - IO_L6N_T0U_N11_AD6N_72
set_property -dict {PACKAGE_PIN T24  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[2]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ2"       - IO_L6P_T0U_N10_AD6P_72
set_property -dict {PACKAGE_PIN N23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[4]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ4"       - IO_L3N_T0L_N5_AD15N_72
set_property -dict {PACKAGE_PIN P23  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[6]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ6"       - IO_L3P_T0L_N4_AD15P_72
set_property -dict {PACKAGE_PIN P21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[5]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ5"       - IO_L2N_T0L_N3_72
set_property -dict {PACKAGE_PIN R21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[7]    ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQ7"       - IO_L2P_T0L_N2_72
set_property -dict {PACKAGE_PIN N21  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[1] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_C9"    - IO_L1N_T0L_N1_DBC_72
set_property -dict {PACKAGE_PIN N22  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[1] ]; # Bank 72  VCCO - VCC1V2 Net "DDR4_C3_DQS_T9"    - IO_L1P_T0L_N0_DBC_72
set_property -dict {PACKAGE_PIN B21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[43]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ43"      - IO_L23N_T3U_N9_71
set_property -dict {PACKAGE_PIN C21  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[42]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ42"      - IO_L23P_T3U_N8_71
set_property -dict {PACKAGE_PIN B17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[10]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C5"    - IO_L22N_T3U_N7_DBC_AD0N_71
set_property -dict {PACKAGE_PIN C17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[10]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T5"    - IO_L22P_T3U_N6_DBC_AD0P_71
#set_property -dict {PACKAGE_PIN D18  IOSTANDARD LVCMOS12       } [get_ports c3_ddr4_event_n  ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_EVENT_B"   - IO_T3U_N12_71
set_property -dict {PACKAGE_PIN C18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[41]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ41"      - IO_L24N_T3U_N11_71
set_property -dict {PACKAGE_PIN C19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[40]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ40"      - IO_L24P_T3U_N10_71
set_property -dict {PACKAGE_PIN A20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[46]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ46"      - IO_L21N_T3L_N5_AD8N_71
set_property -dict {PACKAGE_PIN B20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[47]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ47"      - IO_L21P_T3L_N4_AD8P_71
set_property -dict {PACKAGE_PIN A17  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[45]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ45"      - IO_L20N_T3L_N3_AD1N_71
set_property -dict {PACKAGE_PIN A18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[44]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ44"      - IO_L20P_T3L_N2_AD1P_71
set_property -dict {PACKAGE_PIN A19  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[11]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C14"   - IO_L19N_T3L_N1_DBC_AD9N_71
set_property -dict {PACKAGE_PIN B19  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[11]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T14"   - IO_L19P_T3L_N0_DBC_AD9P_71
set_property -dict {PACKAGE_PIN E20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[51]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ51"      - IO_L17N_T2U_N9_AD10N_71
set_property -dict {PACKAGE_PIN F20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[49]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ49"      - IO_L17P_T2U_N8_AD10P_71
set_property -dict {PACKAGE_PIN F17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[12]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C6"    - IO_L16N_T2U_N7_QBC_AD3N_71
set_property -dict {PACKAGE_PIN F18  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[12]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T6"    - IO_L16P_T2U_N6_QBC_AD3P_71
set_property -dict {PACKAGE_PIN D21  IOSTANDARD LVCMOS12       } [get_ports c3_ddr4_reset_n  ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_RESET_N"   - IO_T2U_N12_71
set_property -dict {PACKAGE_PIN E17  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[48]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ48"      - IO_L18N_T2U_N11_AD2N_71
set_property -dict {PACKAGE_PIN E18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[50]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ50"      - IO_L18P_T2U_N10_AD2P_71
set_property -dict {PACKAGE_PIN D19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[52]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ52"      - IO_L15N_T2L_N5_AD11N_71
set_property -dict {PACKAGE_PIN D20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[53]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ53"      - IO_L15P_T2L_N4_AD11P_71
set_property -dict {PACKAGE_PIN H18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[54]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ54"      - IO_L14N_T2L_N3_GC_71
set_property -dict {PACKAGE_PIN J18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[55]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ55"      - IO_L14P_T2L_N2_GC_71
set_property -dict {PACKAGE_PIN G19  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[13]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C15"   - IO_L13N_T2L_N1_GC_QBC_71
set_property -dict {PACKAGE_PIN H19  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[13]]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T15"   - IO_L13P_T2L_N0_GC_QBC_71
set_property -dict {PACKAGE_PIN F19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[18]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ18"      - IO_L11N_T1U_N9_GC_71
set_property -dict {PACKAGE_PIN G20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[16]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ16"      - IO_L11P_T1U_N8_GC_71
set_property -dict {PACKAGE_PIN K20  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[4] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C2"    - IO_L10N_T1U_N7_QBC_AD4N_71
set_property -dict {PACKAGE_PIN L20  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[4] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T2"    - IO_L10P_T1U_N6_QBC_AD4P_71
set_property -dict {PACKAGE_PIN G17  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[19]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ19"      - IO_L12N_T1U_N11_GC_71
set_property -dict {PACKAGE_PIN H17  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[17]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ17"      - IO_L12P_T1U_N10_GC_71
set_property -dict {PACKAGE_PIN J19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[23]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ23"      - IO_L9N_T1L_N5_AD12N_71
set_property -dict {PACKAGE_PIN J20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[20]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ20"      - IO_L9P_T1L_N4_AD12P_71
set_property -dict {PACKAGE_PIN L18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[22]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ22"      - IO_L8N_T1L_N3_AD5N_71
set_property -dict {PACKAGE_PIN L19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[21]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ21"      - IO_L8P_T1L_N2_AD5P_71
set_property -dict {PACKAGE_PIN K17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[5] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C11"   - IO_L7N_T1L_N1_QBC_AD13N_71
set_property -dict {PACKAGE_PIN K18  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[5] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T11"   - IO_L7P_T1L_N0_QBC_AD13P_71
set_property -dict {PACKAGE_PIN M19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[24]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ24"      - IO_L5N_T0U_N9_AD14N_71
set_property -dict {PACKAGE_PIN M20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[25]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ25"      - IO_L5P_T0U_N8_AD14P_71
set_property -dict {PACKAGE_PIN P18  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[6] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C3"    - IO_L4N_T0U_N7_DBC_AD7N_71
set_property -dict {PACKAGE_PIN P19  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[6] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T3"    - IO_L4P_T0U_N6_DBC_AD7P_71
set_property -dict {PACKAGE_PIN R17  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[27]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ27"      - IO_L6N_T0U_N11_AD6N_71
set_property -dict {PACKAGE_PIN R18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[26]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ26"      - IO_L6P_T0U_N10_AD6P_71
set_property -dict {PACKAGE_PIN N18  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[30]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ30"      - IO_L3N_T0L_N5_AD15N_71
set_property -dict {PACKAGE_PIN N19  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[31]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ31"      - IO_L3P_T0L_N4_AD15P_71
set_property -dict {PACKAGE_PIN R20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[28]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ28"      - IO_L2N_T0L_N3_71
set_property -dict {PACKAGE_PIN T20  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[29]   ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQ29"      - IO_L2P_T0L_N2_71
set_property -dict {PACKAGE_PIN M17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[7] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_C12"   - IO_L1N_T0L_N1_DBC_71
set_property -dict {PACKAGE_PIN N17  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[7] ]; # Bank 71  VCCO - VCC1V2 Net "DDR4_C3_DQS_T12"   - IO_L1P_T0L_N0_DBC_71
set_property -dict {PACKAGE_PIN B16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cs_n[0]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CS_B0"     - IO_L23N_T3U_N9_70
set_property -dict {PACKAGE_PIN C16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_odt[0]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ODT0"      - IO_L23P_T3U_N8_70
set_property -dict {PACKAGE_PIN C13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[11]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR11"     - IO_L22N_T3U_N7_DBC_AD0N_70
set_property -dict {PACKAGE_PIN D13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_bg[0]    ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_BG0"       - IO_L22P_T3U_N6_DBC_AD0P_70
#set_property -dict {PACKAGE_PIN D16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cs_n[1]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CS_B1"     - IO_T3U_N12_70
set_property -dict {PACKAGE_PIN A13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[9]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR9"      - IO_L24N_T3U_N11_70
set_property -dict {PACKAGE_PIN B13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[12]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR12"     - IO_L24P_T3U_N10_70
set_property -dict {PACKAGE_PIN A15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[3]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR3"      - IO_L21N_T3L_N5_AD8N_70
set_property -dict {PACKAGE_PIN B15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[1]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR1"      - IO_L21P_T3L_N4_AD8P_70
set_property -dict {PACKAGE_PIN C14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[4]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR4"      - IO_L20N_T3L_N3_AD1N_70
set_property -dict {PACKAGE_PIN D14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[10]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR10"     - IO_L20P_T3L_N2_AD1P_70
set_property -dict {PACKAGE_PIN A14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[5]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR5"      - IO_L19N_T3L_N1_DBC_AD9N_70
set_property -dict {PACKAGE_PIN B14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[6]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR6"      - IO_L19P_T3L_N0_DBC_AD9P_70
set_property -dict {PACKAGE_PIN E15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[15]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR15"     - IO_L17N_T2U_N9_AD10N_70
#set_property -dict {PACKAGE_PIN E16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_odt[1]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ODT1"      - IO_L17P_T2U_N8_AD10P_70
#set_property -dict {PACKAGE_PIN G13  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c3_ddr4_ck_c[1]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CK_C1"     - IO_L16N_T2U_N7_QBC_AD3N_70
#set_property -dict {PACKAGE_PIN G14  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c3_ddr4_ck_t[1]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CK_T1"     - IO_L16P_T2U_N6_QBC_AD3P_70
set_property -dict {PACKAGE_PIN D15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[14]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR14"     - IO_T2U_N12_70
set_property -dict {PACKAGE_PIN F14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[2]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR2"      - IO_L18N_T2U_N11_AD2N_70
set_property -dict {PACKAGE_PIN F15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[16]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR16"     - IO_L18P_T2U_N10_AD2P_70
set_property -dict {PACKAGE_PIN E13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[7]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR7"      - IO_L15N_T2L_N5_AD11N_70
set_property -dict {PACKAGE_PIN F13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[8]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR8"      - IO_L15P_T2L_N4_AD11P_70
set_property -dict {PACKAGE_PIN H13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_act_n    ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ACT_B"     - IO_L14N_T2L_N3_GC_70
set_property -dict {PACKAGE_PIN H14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_ba[1]    ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_BA1"       - IO_L14P_T2L_N2_GC_70
#set_property -dict {PACKAGE_PIN G15  IOSTANDARD LVCMOS12       } [get_ports c3_ddr4_alert_n  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ALERT_B"  - IO_L11N_T1U_N9_GC_70
#set_property -dict {PACKAGE_PIN G16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[17]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR17"    - IO_L11P_T1U_N8_GC_70
set_property -dict {PACKAGE_PIN L13  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c3_ddr4_ck_c[0]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CK_C0"    - IO_L10N_T1U_N7_QBC_AD4N_70
set_property -dict {PACKAGE_PIN L14  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c3_ddr4_ck_t[0]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CK_T0"    - IO_L10P_T1U_N6_QBC_AD4P_70
set_property -dict {PACKAGE_PIN K13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cke[0]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CKE0"     - IO_T1U_N12_70
set_property -dict {PACKAGE_PIN J13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_bg[1]    ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_BG1"      - IO_L12N_T1U_N11_GC_70
set_property -dict {PACKAGE_PIN J14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_par   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_PAR"      - IO_L12P_T1U_N10_GC_70
set_property -dict {PACKAGE_PIN J15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_ba[0]    ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_BA0"      - IO_L9N_T1L_N5_AD12N_70
set_property -dict {PACKAGE_PIN K16  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[13]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR13"    - IO_L9P_T1L_N4_AD12P_70
#set_property -dict {PACKAGE_PIN M13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cs_n[3]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CS_B3"    - IO_L8N_T1L_N3_AD5N_70
#set_property -dict {PACKAGE_PIN M14  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cs_n[2]  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CS_B2"    - IO_L8P_T1L_N2_AD5P_70
set_property -dict {PACKAGE_PIN K15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_adr[0]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ADR0"     - IO_L7N_T1L_N1_QBC_AD13N_70
#set_property -dict {PACKAGE_PIN L15  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_cke[1]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_CKE1"     - IO_L7P_T1L_N0_QBC_AD13P_70
set_property -dict {PACKAGE_PIN N13  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[66]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ66"     - IO_L5N_T0U_N9_AD14N_70
set_property -dict {PACKAGE_PIN N14  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[67]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ67"     - IO_L5P_T0U_N8_AD14P_70
set_property -dict {PACKAGE_PIN P15  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[16]]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQS_C8"   - IO_L4N_T0U_N7_DBC_AD7N_70
set_property -dict {PACKAGE_PIN R16  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[16]]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQS_T8"   - IO_L4P_T0U_N6_DBC_AD7P_70
set_property -dict {PACKAGE_PIN M16  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[64]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ64"     - IO_L6N_T0U_N11_AD6N_70
set_property -dict {PACKAGE_PIN N16  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[65]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ65"     - IO_L6P_T0U_N10_AD6P_70
set_property -dict {PACKAGE_PIN P13  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[70]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ70"     - IO_L3N_T0L_N5_AD15N_70
set_property -dict {PACKAGE_PIN P14  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[71]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ71"     - IO_L3P_T0L_N4_AD15P_70
set_property -dict {PACKAGE_PIN R15  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[69]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ69"     - IO_L2N_T0L_N3_70
set_property -dict {PACKAGE_PIN T15  IOSTANDARD POD12_DCI      } [get_ports c3_ddr4_dq[68]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ68"     - IO_L2P_T0L_N2_70
set_property -dict {PACKAGE_PIN R13  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_c[17]]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQS_C17"  - IO_L1N_T0L_N1_DBC_70
set_property -dict {PACKAGE_PIN T13  IOSTANDARD DIFF_POD12_DCI } [get_ports c3_ddr4_dqs_t[17]]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQS_T17"  - IO_L1P_T0L_N0_DBC_70  