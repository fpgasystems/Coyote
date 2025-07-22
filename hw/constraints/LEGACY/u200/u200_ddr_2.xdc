# DDR clocks
set_property	PACKAGE_PIN	E32		            [get_ports 	c2_sys_clk_n] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c2_sys_clk_n] ; 
set_property	PACKAGE_PIN	F32		            [get_ports 	c2_sys_clk_p] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c2_sys_clk_p] ; 

####
### DDR4 c2
####

set_property -dict {PACKAGE_PIN C26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[25]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ25"    - IO_L23N_T3U_N9_48
set_property -dict {PACKAGE_PIN D26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[24]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ24"    - IO_L23P_T3U_N8_48
set_property -dict {PACKAGE_PIN A28  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[6] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C3"  - IO_L22N_T3U_N7_DBC_AD0N_48
set_property -dict {PACKAGE_PIN A27  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[6] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T3"  - IO_L22P_T3U_N6_DBC_AD0P_48
set_property -dict {PACKAGE_PIN B27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[26]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ26"    - IO_L24N_T3U_N11_48
set_property -dict {PACKAGE_PIN B26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[27]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ27"    - IO_L24P_T3U_N10_48
set_property -dict {PACKAGE_PIN C28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[31]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ31"    - IO_L21N_T3L_N5_AD8N_48
set_property -dict {PACKAGE_PIN C27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[30]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ30"    - IO_L21P_T3L_N4_AD8P_48
set_property -dict {PACKAGE_PIN A30  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[29]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ29"    - IO_L20N_T3L_N3_AD1N_48
set_property -dict {PACKAGE_PIN A29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[28]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ28"    - IO_L20P_T3L_N2_AD1P_48
set_property -dict {PACKAGE_PIN B29  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[7] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C12" - IO_L19N_T3L_N1_DBC_AD9N_48
set_property -dict {PACKAGE_PIN C29  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[7] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T12" - IO_L19P_T3L_N0_DBC_AD9P_48
set_property -dict {PACKAGE_PIN E27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[17]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ17"    - IO_L17N_T2U_N9_AD10N_48
set_property -dict {PACKAGE_PIN F27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[16]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ16"    - IO_L17P_T2U_N8_AD10P_48
set_property -dict {PACKAGE_PIN D30  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[4] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C2"  - IO_L16N_T2U_N7_QBC_AD3N_48
set_property -dict {PACKAGE_PIN D29  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[4] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T2"  - IO_L16P_T2U_N6_QBC_AD3P_48
set_property -dict {PACKAGE_PIN D28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[19]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ19"    - IO_L18N_T2U_N11_AD2N_48
set_property -dict {PACKAGE_PIN E28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[18]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ18"    - IO_L18P_T2U_N10_AD2P_48
set_property -dict {PACKAGE_PIN F29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[23]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ23"    - IO_L15N_T2L_N5_AD11N_48
set_property -dict {PACKAGE_PIN F28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[22]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ22"    - IO_L15P_T2L_N4_AD11P_48
set_property -dict {PACKAGE_PIN G27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[20]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ20"    - IO_L14N_T2L_N3_GC_48
set_property -dict {PACKAGE_PIN G26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[21]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ21"    - IO_L14P_T2L_N2_GC_48
set_property -dict {PACKAGE_PIN H27  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[5] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C11" - IO_L13N_T2L_N1_GC_QBC_48
set_property -dict {PACKAGE_PIN H26  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[5] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T11" - IO_L13P_T2L_N0_GC_QBC_48
set_property -dict {PACKAGE_PIN H28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[10]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ10"    - IO_L11N_T1U_N9_GC_48
set_property -dict {PACKAGE_PIN J28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[8]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ8"     - IO_L11P_T1U_N8_GC_48
set_property -dict {PACKAGE_PIN J26  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[2] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C1"  - IO_L10N_T1U_N7_QBC_AD4N_48
set_property -dict {PACKAGE_PIN J25  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[2] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T1"  - IO_L10P_T1U_N6_QBC_AD4P_48
set_property -dict {PACKAGE_PIN G29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[11]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ11"    - IO_L12N_T1U_N11_GC_48
set_property -dict {PACKAGE_PIN H29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[9]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ9"     - IO_L12P_T1U_N10_GC_48
set_property -dict {PACKAGE_PIN K27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[15]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ15"    - IO_L9N_T1L_N5_AD12N_48
set_property -dict {PACKAGE_PIN L27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[13]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ13"    - IO_L9P_T1L_N4_AD12P_48
set_property -dict {PACKAGE_PIN K26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[14]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ14"    - IO_L8N_T1L_N3_AD5N_48
set_property -dict {PACKAGE_PIN K25  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[12]   ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ12"    - IO_L8P_T1L_N2_AD5P_48
set_property -dict {PACKAGE_PIN L28  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[3] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C10" - IO_L7N_T1L_N1_QBC_AD13N_48
set_property -dict {PACKAGE_PIN M27  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[3] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T10" - IO_L7P_T1L_N0_QBC_AD13P_48
set_property -dict {PACKAGE_PIN P25  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[1]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ1"     - IO_L5N_T0U_N9_AD14N_48
set_property -dict {PACKAGE_PIN R25  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[0]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ0"     - IO_L5P_T0U_N8_AD14P_48
set_property -dict {PACKAGE_PIN M26  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[0] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C0"  - IO_L4N_T0U_N7_DBC_AD7N_48
set_property -dict {PACKAGE_PIN N26  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[0] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T0"  - IO_L4P_T0U_N6_DBC_AD7P_48
set_property -dict {PACKAGE_PIN L25  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[3]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ3"     - IO_L6N_T0U_N11_AD6N_48
set_property -dict {PACKAGE_PIN M25  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[2]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ2"     - IO_L6P_T0U_N10_AD6P_48
set_property -dict {PACKAGE_PIN P26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[4]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ4"     - IO_L3N_T0L_N5_AD15N_48
set_property -dict {PACKAGE_PIN R26  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[5]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ5"     - IO_L3P_T0L_N4_AD15P_48
set_property -dict {PACKAGE_PIN N28  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[7]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ7"     - IO_L2N_T0L_N3_48
set_property -dict {PACKAGE_PIN N27  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[6]    ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQ6"     - IO_L2P_T0L_N2_48
set_property -dict {PACKAGE_PIN P28  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[1] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_C9"  - IO_L1N_T0L_N1_DBC_48
set_property -dict {PACKAGE_PIN R28  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[1] ]; # Bank 48 VCCO - VCC1V2 Net "DDR4_C2_DQS_T9"  - IO_L1P_T0L_N0_DBC_48
set_property -dict {PACKAGE_PIN B32  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[7]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR7"    - IO_L23N_T3U_N9_47
set_property -dict {PACKAGE_PIN B31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_act_n    ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ACT_B"   - IO_L23P_T3U_N8_47
set_property -dict {PACKAGE_PIN A35  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[14]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR14"   - IO_L22N_T3U_N7_DBC_AD0N_47
set_property -dict {PACKAGE_PIN A34  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[10]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR10"   - IO_L22P_T3U_N6_DBC_AD0P_47
set_property -dict {PACKAGE_PIN C31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_bg[0]    ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_BG0"     - IO_T3U_N12_47
set_property -dict {PACKAGE_PIN A33  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[1]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR1"    - IO_L24N_T3U_N11_47
set_property -dict {PACKAGE_PIN A32  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[8]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR8"    - IO_L24P_T3U_N10_47
set_property -dict {PACKAGE_PIN C33  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[2]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR2"    - IO_L21N_T3L_N5_AD8N_47
set_property -dict {PACKAGE_PIN C32  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[6]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR6"    - IO_L21P_T3L_N4_AD8P_47
set_property -dict {PACKAGE_PIN B36  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_ba[1]    ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_BA1"     - IO_L20N_T3L_N3_AD1N_47
set_property -dict {PACKAGE_PIN B35  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cs_n[0]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CS_B0"   - IO_L20P_T3L_N2_AD1P_47
set_property -dict {PACKAGE_PIN B34  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_ck_c[0]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CK_C0"   - IO_L19N_T3L_N1_DBC_AD9N_47
set_property -dict {PACKAGE_PIN C34  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_ck_t[0]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CK_T0"   - IO_L19P_T3L_N0_DBC_AD9P_47
set_property -dict {PACKAGE_PIN J30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_bg[1]    ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_BG1"     - IO_L17N_T2U_N9_AD10N_47
set_property -dict {PACKAGE_PIN J29  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[3]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR3"    - IO_L17P_T2U_N8_AD10P_47
#set_property -dict {PACKAGE_PIN D35  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_ck_c[1]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CK_C1"   - IO_L16N_T2U_N7_QBC_AD3N_47
#set_property -dict {PACKAGE_PIN D34  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_ck_t[1]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CK_T1"   - IO_L16P_T2U_N6_QBC_AD3P_47
#set_property -dict {PACKAGE_PIN E30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cke[1]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CKE1"    - IO_T2U_N12_47
set_property -dict {PACKAGE_PIN D31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[9]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR9"    - IO_L18N_T2U_N11_AD2N_47
set_property -dict {PACKAGE_PIN E31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[11]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR11"   - IO_L18P_T2U_N10_AD2P_47
#set_property -dict {PACKAGE_PIN K31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cs_n[3]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CS_B3"   - IO_L15N_T2L_N5_AD11N_47
set_property -dict {PACKAGE_PIN K30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[16]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR16"   - IO_L15P_T2L_N4_AD11P_47
set_property -dict {PACKAGE_PIN D33  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_ba[0]    ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_BA0"     - IO_L14N_T2L_N3_GC_47
set_property -dict {PACKAGE_PIN E33  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_odt[0]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ODT0"    - IO_L14P_T2L_N2_GC_47
set_property -dict {PACKAGE_PIN F30  IOSTANDARD LVCMOS12       } [get_ports c2_ddr4_alert_n  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ALERT_B" - IO_L11N_T1U_N9_GC_47
set_property -dict {PACKAGE_PIN G30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cke[0]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CKE0"    - IO_L11P_T1U_N8_GC_47
set_property -dict {PACKAGE_PIN G32  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[15]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR15"   - IO_L10N_T1U_N7_QBC_AD4N_47
set_property -dict {PACKAGE_PIN G31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[5]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR5"    - IO_L10P_T1U_N6_QBC_AD4P_47
#set_property -dict {PACKAGE_PIN J31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cs_n[1]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CS_B1"   - IO_T1U_N12_47
#set_property -dict {PACKAGE_PIN F34  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_odt[1]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ODT1"    - IO_L12N_T1U_N11_GC_47
set_property -dict {PACKAGE_PIN F33  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[13]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR13"   - IO_L12P_T1U_N10_GC_47
#set_property -dict {PACKAGE_PIN L30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_cs_n[2]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_CS_B2"   - IO_L9N_T1L_N5_AD12N_47
set_property -dict {PACKAGE_PIN L29  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[0]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR0"    - IO_L9P_T1L_N4_AD12P_47
#set_property -dict {PACKAGE_PIN H32  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[17]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR17"   - IO_L8N_T1L_N3_AD5N_47
set_property -dict {PACKAGE_PIN H31  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[4]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR4"    - IO_L8P_T1L_N2_AD5P_47
set_property -dict {PACKAGE_PIN M30  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_adr[12]  ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_ADR12"   - IO_L7N_T1L_N1_QBC_AD13N_47
set_property -dict {PACKAGE_PIN M29  IOSTANDARD SSTL12_DCI     } [get_ports c2_ddr4_par   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_PAR"     - IO_L7P_T1L_N0_QBC_AD13P_47
set_property -dict {PACKAGE_PIN P30  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[40]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ40"    - IO_L5N_T0U_N9_AD14N_47
set_property -dict {PACKAGE_PIN R30  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[41]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ41"    - IO_L5P_T0U_N8_AD14P_47
set_property -dict {PACKAGE_PIN M31  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[10]]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQS_C5"  - IO_L4N_T0U_N7_DBC_AD7N_47
set_property -dict {PACKAGE_PIN N31  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[10]]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQS_T5"  - IO_L4P_T0U_N6_DBC_AD7P_47
set_property -dict {PACKAGE_PIN N29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[43]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ43"    - IO_L6N_T0U_N11_AD6N_47
set_property -dict {PACKAGE_PIN P29  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[42]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ42"    - IO_L6P_T0U_N10_AD6P_47
set_property -dict {PACKAGE_PIN N32  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[47]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ47"    - IO_L3N_T0L_N5_AD15N_47
set_property -dict {PACKAGE_PIN P31  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[46]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ46"    - IO_L3P_T0L_N4_AD15P_47
set_property -dict {PACKAGE_PIN L32  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[44]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ44"    - IO_L2N_T0L_N3_47
set_property -dict {PACKAGE_PIN M32  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[45]   ]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQ45"    - IO_L2P_T0L_N2_47
set_property -dict {PACKAGE_PIN R31  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[11]]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQS_C14" - IO_L1N_T0L_N1_DBC_47
set_property -dict {PACKAGE_PIN T30  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[11]]; # Bank 47 VCCO - VCC1V2 Net "DDR4_C2_DQS_T14" - IO_L1P_T0L_N0_DBC_47
set_property -dict {PACKAGE_PIN B37  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[65]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ65"    - IO_L23N_T3U_N9_46
set_property -dict {PACKAGE_PIN C36  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[64]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ64"    - IO_L23P_T3U_N8_46
set_property -dict {PACKAGE_PIN A39  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[16]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C8"  - IO_L22N_T3U_N7_DBC_AD0N_46
set_property -dict {PACKAGE_PIN B39  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[16]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T8"  - IO_L22P_T3U_N6_DBC_AD0P_46
#set_property -dict {PACKAGE_PIN D40  IOSTANDARD LVCMOS12       } [get_ports c2_ddr4_event_n  ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_EVENT_B" - IO_T3U_N12_46
set_property -dict {PACKAGE_PIN A38  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[67]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ67"    - IO_L24N_T3U_N11_46
set_property -dict {PACKAGE_PIN A37  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[66]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ66"    - IO_L24P_T3U_N10_46
set_property -dict {PACKAGE_PIN C39  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[68]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ68"    - IO_L21N_T3L_N5_AD8N_46
set_property -dict {PACKAGE_PIN D39  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[69]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ69"    - IO_L21P_T3L_N4_AD8P_46
set_property -dict {PACKAGE_PIN A40  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[70]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ70"    - IO_L20N_T3L_N3_AD1N_46
set_property -dict {PACKAGE_PIN B40  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[71]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ71"    - IO_L20P_T3L_N2_AD1P_46
set_property -dict {PACKAGE_PIN C38  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[17]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C17" - IO_L19N_T3L_N1_DBC_AD9N_46
set_property -dict {PACKAGE_PIN C37  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[17]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T17" - IO_L19P_T3L_N0_DBC_AD9P_46
set_property -dict {PACKAGE_PIN E35  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[35]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ35"    - IO_L17N_T2U_N9_AD10N_46
set_property -dict {PACKAGE_PIN F35  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[32]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ32"    - IO_L17P_T2U_N8_AD10P_46
set_property -dict {PACKAGE_PIN E40  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[8] ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C4"  - IO_L16N_T2U_N7_QBC_AD3N_46
set_property -dict {PACKAGE_PIN E39  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[8] ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T4"  - IO_L16P_T2U_N6_QBC_AD3P_46
set_property -dict {PACKAGE_PIN D36  IOSTANDARD LVCMOS12       } [get_ports c2_ddr4_reset_n  ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_RESET_N" - IO_T2U_N12_46
set_property -dict {PACKAGE_PIN D38  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[34]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ34"    - IO_L18N_T2U_N11_AD2N_46
set_property -dict {PACKAGE_PIN E38  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_dq[33]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ33"    - IO_L18P_T2U_N10_AD2P_46
set_property -dict {PACKAGE_PIN F38  IOSTANDARD DIFF_SSTL12_DCI} [get_ports c2_ddr4_dq[38]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ38"    - IO_L15N_T2L_N5_AD11N_46
set_property -dict {PACKAGE_PIN G38  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[39]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ39"    - IO_L15P_T2L_N4_AD11P_46
set_property -dict {PACKAGE_PIN E37  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[37]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ37"    - IO_L14N_T2L_N3_GC_46
set_property -dict {PACKAGE_PIN E36  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[36]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ36"    - IO_L14P_T2L_N2_GC_46
set_property -dict {PACKAGE_PIN F37  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[9] ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C13" - IO_L13N_T2L_N1_GC_QBC_46
set_property -dict {PACKAGE_PIN G37  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[9] ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T13" - IO_L13P_T2L_N0_GC_QBC_46
set_property -dict {PACKAGE_PIN G36  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[57]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ57"    - IO_L11N_T1U_N9_GC_46
set_property -dict {PACKAGE_PIN H36  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[56]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ56"    - IO_L11P_T1U_N8_GC_46
set_property -dict {PACKAGE_PIN H38  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[14]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C7"  - IO_L10N_T1U_N7_QBC_AD4N_46
set_property -dict {PACKAGE_PIN J38  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[14]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T7"  - IO_L10P_T1U_N6_QBC_AD4P_46
set_property -dict {PACKAGE_PIN H37  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[58]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ58"    - IO_L12N_T1U_N11_GC_46
set_property -dict {PACKAGE_PIN J36  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[59]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ59"    - IO_L12P_T1U_N10_GC_46
set_property -dict {PACKAGE_PIN G35  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[62]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ62"    - IO_L9N_T1L_N5_AD12N_46
set_property -dict {PACKAGE_PIN G34  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[63]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ63"    - IO_L9P_T1L_N4_AD12P_46
set_property -dict {PACKAGE_PIN K38  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[61]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ61"    - IO_L8N_T1L_N3_AD5N_46
set_property -dict {PACKAGE_PIN K37  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[60]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ60"    - IO_L8P_T1L_N2_AD5P_46
set_property -dict {PACKAGE_PIN H34  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[15]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C16" - IO_L7N_T1L_N1_QBC_AD13N_46
set_property -dict {PACKAGE_PIN H33  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[15]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T16" - IO_L7P_T1L_N0_QBC_AD13P_46
set_property -dict {PACKAGE_PIN K33  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[51]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ51"    - IO_L5N_T0U_N9_AD14N_46
set_property -dict {PACKAGE_PIN L33  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[50]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ50"    - IO_L5P_T0U_N8_AD14P_46
set_property -dict {PACKAGE_PIN L36  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[12]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C6"  - IO_L4N_T0U_N7_DBC_AD7N_46
set_property -dict {PACKAGE_PIN L35  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[12]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T6"  - IO_L4P_T0U_N6_DBC_AD7P_46
set_property -dict {PACKAGE_PIN J35  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[48]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ48"    - IO_L6N_T0U_N11_AD6N_46
set_property -dict {PACKAGE_PIN K35  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[49]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ49"    - IO_L6P_T0U_N10_AD6P_46
set_property -dict {PACKAGE_PIN J34  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[52]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ52"    - IO_L3N_T0L_N5_AD15N_46
set_property -dict {PACKAGE_PIN J33  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[53]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ53"    - IO_L3P_T0L_N4_AD15P_46
set_property -dict {PACKAGE_PIN N34  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[54]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ54"    - IO_L2N_T0L_N3_46
set_property -dict {PACKAGE_PIN P34  IOSTANDARD POD12_DCI      } [get_ports c2_ddr4_dq[55]   ]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQ55"    - IO_L2P_T0L_N2_46
set_property -dict {PACKAGE_PIN L34  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_c[13]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_C15" - IO_L1N_T0L_N1_DBC_46
set_property -dict {PACKAGE_PIN M34  IOSTANDARD DIFF_POD12_DCI } [get_ports c2_ddr4_dqs_t[13]]; # Bank 46 VCCO - VCC1V2 Net "DDR4_C2_DQS_T15" - IO_L1P_T0L_N0_DBC_46
