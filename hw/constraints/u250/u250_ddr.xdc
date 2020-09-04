# DDR clocks
set_property	PACKAGE_PIN	AY38		        [get_ports 	c0_sys_clk_n] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c0_sys_clk_n] ; 
set_property	PACKAGE_PIN	AY37		        [get_ports 	c0_sys_clk_p] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c0_sys_clk_p] ; 

set_property	PACKAGE_PIN	AW19		        [get_ports 	c1_sys_clk_n] ; 
set_property	IOSTANDARD		LVDS	        [get_ports 	c1_sys_clk_n] ; 
set_property	PACKAGE_PIN	AW20		        [get_ports 	c1_sys_clk_p] ; 
set_property	IOSTANDARD		LVDS	        [get_ports 	c1_sys_clk_p] ; 

set_property	PACKAGE_PIN	E32		            [get_ports 	c2_sys_clk_n] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c2_sys_clk_n] ; 
set_property	PACKAGE_PIN	F32		            [get_ports 	c2_sys_clk_p] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c2_sys_clk_p] ; 

set_property	PACKAGE_PIN	H16		            [get_ports 	c3_sys_clk_n] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c3_sys_clk_n] ; 
set_property	PACKAGE_PIN	J16		            [get_ports 	c3_sys_clk_p] ; 
set_property	IOSTANDARD		DIFF_POD12_DCI	[get_ports 	c3_sys_clk_p] ; 

####
### DDR4 c0
####

set_property -dict {PACKAGE_PIN AR36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[16]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR16"   - IO_L23N_T3U_N9_42
set_property -dict {PACKAGE_PIN AP36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[15]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR15"   - IO_L23P_T3U_N8_42
#set_property -dict {PACKAGE_PIN AN34 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_odt[1]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ODT1"    - IO_L22N_T3U_N7_DBC_AD0N_42
#set_property -dict {PACKAGE_PIN AM34 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cs_n[3]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CS_B3"   - IO_L22P_T3U_N6_DBC_AD0P_42
set_property -dict {PACKAGE_PIN AR33 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cs_n[0]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CS_B0"   - IO_T3U_N12_42
set_property -dict {PACKAGE_PIN AN36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[13]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR13"   - IO_L24N_T3U_N11_42
#set_property -dict {PACKAGE_PIN AN35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[17]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR17"   - IO_L24P_T3U_N10_42
set_property -dict {PACKAGE_PIN AP35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[14]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR14"   - IO_L21N_T3L_N5_AD8N_42
set_property -dict {PACKAGE_PIN AP34 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_odt[0]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ODT0"    - IO_L21P_T3L_N4_AD8P_42
#set_property -dict {PACKAGE_PIN AP33 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cs_n[1]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CS_B1"   - IO_L20N_T3L_N3_AD1N_42
#set_property -dict {PACKAGE_PIN AN33 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cs_n[2]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CS_B2"   - IO_L20P_T3L_N2_AD1P_42
set_property -dict {PACKAGE_PIN AT35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_ba[0]    ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_BA0"     - IO_L19N_T3L_N1_DBC_AD9N_42
set_property -dict {PACKAGE_PIN AR35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[10]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR10"   - IO_L19P_T3L_N0_DBC_AD9P_42
set_property -dict {PACKAGE_PIN AW38 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c0_ddr4_ck_c[0]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CK_C0"   - IO_L17N_T2U_N9_AD10N_42
set_property -dict {PACKAGE_PIN AV38 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c0_ddr4_ck_t[0]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CK_T0"   - IO_L17P_T2U_N8_AD10P_42
#set_property -dict {PACKAGE_PIN AU35 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c0_ddr4_ck_c[1]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CK_C1"   - IO_L16N_T2U_N7_QBC_AD3N_42
#set_property -dict {PACKAGE_PIN AU34 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c0_ddr4_ck_t[1]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CK_T1"   - IO_L16P_T2U_N6_QBC_AD3P_42
set_property -dict {PACKAGE_PIN AT34 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_ba[1]    ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_BA1"     - IO_T2U_N12_42
set_property -dict {PACKAGE_PIN AU36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_par   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_PAR"     - IO_L18N_T2U_N11_AD2N_42
set_property -dict {PACKAGE_PIN AT36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[0]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR0"    - IO_L18P_T2U_N10_AD2P_42
set_property -dict {PACKAGE_PIN AV37 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[2]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR2"    - IO_L15N_T2L_N5_AD11N_42
set_property -dict {PACKAGE_PIN AV36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[1]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR1"    - IO_L15P_T2L_N4_AD11P_42
set_property -dict {PACKAGE_PIN AW36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[4]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR4"    - IO_L14N_T2L_N3_GC_42
set_property -dict {PACKAGE_PIN AW35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[3]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR3"    - IO_L14P_T2L_N2_GC_42
set_property -dict {PACKAGE_PIN BA38 IOSTANDARD LVCMOS12       } [get_ports c0_ddr4_alert_n  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ALERT_B" - IO_L11N_T1U_N9_GC_42
set_property -dict {PACKAGE_PIN BA37 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[8]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR8"    - IO_L11P_T1U_N8_GC_42
set_property -dict {PACKAGE_PIN BA40 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[7]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR7"    - IO_L10N_T1U_N7_QBC_AD4N_42
set_property -dict {PACKAGE_PIN BA39 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[11]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR11"   - IO_L10P_T1U_N6_QBC_AD4P_42
set_property -dict {PACKAGE_PIN BB37 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[9]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR9"    - IO_T1U_N12_42
set_property -dict {PACKAGE_PIN AY36 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[5]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR5"    - IO_L12N_T1U_N11_GC_42
set_property -dict {PACKAGE_PIN AY35 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[6]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR6"    - IO_L12P_T1U_N10_GC_42
#set_property -dict {PACKAGE_PIN BC40 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cke[1]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CKE1"    - IO_L9N_T1L_N5_AD12N_42
set_property -dict {PACKAGE_PIN BC39 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_bg[1]    ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_BG1"     - IO_L9P_T1L_N4_AD12P_42
set_property -dict {PACKAGE_PIN BB40 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_adr[12]  ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ADR12"   - IO_L8N_T1L_N3_AD5N_42
set_property -dict {PACKAGE_PIN BB39 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_act_n    ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_ACT_B"   - IO_L8P_T1L_N2_AD5P_42
set_property -dict {PACKAGE_PIN BC38 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_cke[0]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_CKE0"    - IO_L7N_T1L_N1_QBC_AD13N_42
set_property -dict {PACKAGE_PIN BC37 IOSTANDARD SSTL12_DCI     } [get_ports c0_ddr4_bg[0]    ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_BG0"     - IO_L7P_T1L_N0_QBC_AD13P_42
set_property -dict {PACKAGE_PIN BF43 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[66]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ66"    - IO_L5N_T0U_N9_AD14N_42
set_property -dict {PACKAGE_PIN BF42 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[67]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ67"    - IO_L5P_T0U_N8_AD14P_42
set_property -dict {PACKAGE_PIN BF38 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[16]]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQS_C8"  - IO_L4N_T0U_N7_DBC_AD7N_42
set_property -dict {PACKAGE_PIN BE38 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[16]]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQS_T8"  - IO_L4P_T0U_N6_DBC_AD7P_42
set_property -dict {PACKAGE_PIN BD40 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[64]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ64"    - IO_L6N_T0U_N11_AD6N_42
set_property -dict {PACKAGE_PIN BD39 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[65]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ65"    - IO_L6P_T0U_N10_AD6P_42
set_property -dict {PACKAGE_PIN BF41 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[71]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ71"    - IO_L3N_T0L_N5_AD15N_42
set_property -dict {PACKAGE_PIN BE40 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[70]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ70"    - IO_L3P_T0L_N4_AD15P_42
set_property -dict {PACKAGE_PIN BF37 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[68]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ68"    - IO_L2N_T0L_N3_42
set_property -dict {PACKAGE_PIN BE37 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[69]   ]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQ69"    - IO_L2P_T0L_N2_42
set_property -dict {PACKAGE_PIN BF40 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[17]]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQS_C17" - IO_L1N_T0L_N1_DBC_42
set_property -dict {PACKAGE_PIN BF39 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[17]]; # Bank 42 VCCO - VCC1V2 Net "DDR4_C0_DQS_T17" - IO_L1P_T0L_N0_DBC_42
set_property -dict {PACKAGE_PIN AU32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[34]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ34"    - IO_L23N_T3U_N9_41
set_property -dict {PACKAGE_PIN AT32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[35]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ35"    - IO_L23P_T3U_N8_41
set_property -dict {PACKAGE_PIN AM32 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[8] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C4"  - IO_L22N_T3U_N7_DBC_AD0N_41
set_property -dict {PACKAGE_PIN AM31 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[8] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T4"  - IO_L22P_T3U_N6_DBC_AD0P_41
#set_property -dict {PACKAGE_PIN AT33 IOSTANDARD LVCMOS12       } [get_ports c0_ddr4_event_n  ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_EVENT_B" - IO_T3U_N12_41
set_property -dict {PACKAGE_PIN AM30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[33]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ33"    - IO_L24N_T3U_N11_41
set_property -dict {PACKAGE_PIN AL30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[32]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ32"    - IO_L24P_T3U_N10_41
set_property -dict {PACKAGE_PIN AR32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[38]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ38"    - IO_L21N_T3L_N5_AD8N_41
set_property -dict {PACKAGE_PIN AR31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[39]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ39"    - IO_L21P_T3L_N4_AD8P_41
set_property -dict {PACKAGE_PIN AN32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[37]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ37"    - IO_L20N_T3L_N3_AD1N_41
set_property -dict {PACKAGE_PIN AN31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[36]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ36"    - IO_L20P_T3L_N2_AD1P_41
set_property -dict {PACKAGE_PIN AP31 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[9] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C13" - IO_L19N_T3L_N1_DBC_AD9N_41
set_property -dict {PACKAGE_PIN AP30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[9] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T13" - IO_L19P_T3L_N0_DBC_AD9P_41
set_property -dict {PACKAGE_PIN AV32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[25]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ25"    - IO_L17N_T2U_N9_AD10N_41
set_property -dict {PACKAGE_PIN AV31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[24]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ24"    - IO_L17P_T2U_N8_AD10P_41
set_property -dict {PACKAGE_PIN AW33 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[6] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C3"  - IO_L16N_T2U_N7_QBC_AD3N_41
set_property -dict {PACKAGE_PIN AV33 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[6] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T3"  - IO_L16P_T2U_N6_QBC_AD3P_41
set_property -dict {PACKAGE_PIN AU31 IOSTANDARD LVCMOS12       } [get_ports c0_ddr4_reset_n  ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_RESET_N" - IO_T2U_N12_41
set_property -dict {PACKAGE_PIN AW34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[27]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ27"    - IO_L18N_T2U_N11_AD2N_41
set_property -dict {PACKAGE_PIN AV34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[26]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ26"    - IO_L18P_T2U_N10_AD2P_41
set_property -dict {PACKAGE_PIN AY31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[29]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ29"    - IO_L15N_T2L_N5_AD11N_41
set_property -dict {PACKAGE_PIN AW31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[28]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ28"    - IO_L15P_T2L_N4_AD11P_41
set_property -dict {PACKAGE_PIN BA35 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[30]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ30"    - IO_L14N_T2L_N3_GC_41
set_property -dict {PACKAGE_PIN BA34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[31]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ31"    - IO_L14P_T2L_N2_GC_41
set_property -dict {PACKAGE_PIN BA33 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[7] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C12" - IO_L13N_T2L_N1_GC_QBC_41
set_property -dict {PACKAGE_PIN BA32 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[7] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T12" - IO_L13P_T2L_N0_GC_QBC_41
set_property -dict {PACKAGE_PIN BB32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[17]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ17"    - IO_L11N_T1U_N9_GC_41
set_property -dict {PACKAGE_PIN BB31 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[16]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ16"    - IO_L11P_T1U_N8_GC_41
set_property -dict {PACKAGE_PIN BB36 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[4] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C2"  - IO_L10N_T1U_N7_QBC_AD4N_41
set_property -dict {PACKAGE_PIN BB35 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[4] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T2"  - IO_L10P_T1U_N6_QBC_AD4P_41
set_property -dict {PACKAGE_PIN AY33 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[19]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ19"    - IO_L12N_T1U_N11_GC_41
set_property -dict {PACKAGE_PIN AY32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[18]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ18"    - IO_L12P_T1U_N10_GC_41
set_property -dict {PACKAGE_PIN BC33 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[21]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ21"    - IO_L9N_T1L_N5_AD12N_41
set_property -dict {PACKAGE_PIN BC32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[20]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ20"    - IO_L9P_T1L_N4_AD12P_41
set_property -dict {PACKAGE_PIN BC34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[23]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ23"    - IO_L8N_T1L_N3_AD5N_41
set_property -dict {PACKAGE_PIN BB34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[22]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ22"    - IO_L8P_T1L_N2_AD5P_41
set_property -dict {PACKAGE_PIN BD31 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[5] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C11" - IO_L7N_T1L_N1_QBC_AD13N_41
set_property -dict {PACKAGE_PIN BC31 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[5] ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T11" - IO_L7P_T1L_N0_QBC_AD13P_41
set_property -dict {PACKAGE_PIN BE33 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[58]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ58"    - IO_L5N_T0U_N9_AD14N_41
set_property -dict {PACKAGE_PIN BD33 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[57]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ57"    - IO_L5P_T0U_N8_AD14P_41
set_property -dict {PACKAGE_PIN BE36 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[14]]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C7"  - IO_L4N_T0U_N7_DBC_AD7N_41
set_property -dict {PACKAGE_PIN BE35 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[14]]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T7"  - IO_L4P_T0U_N6_DBC_AD7P_41
set_property -dict {PACKAGE_PIN BD35 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[59]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ59"    - IO_L6N_T0U_N11_AD6N_41
set_property -dict {PACKAGE_PIN BD34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[56]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ56"    - IO_L6P_T0U_N10_AD6P_41
set_property -dict {PACKAGE_PIN BF33 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[61]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ61"    - IO_L3N_T0L_N5_AD15N_41
set_property -dict {PACKAGE_PIN BF32 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[60]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ60"    - IO_L3P_T0L_N4_AD15P_41
set_property -dict {PACKAGE_PIN BF35 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[63]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ63"    - IO_L2N_T0L_N3_41
set_property -dict {PACKAGE_PIN BF34 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[62]   ]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQ62"    - IO_L2P_T0L_N2_41
set_property -dict {PACKAGE_PIN BE32 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[15]]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_C16" - IO_L1N_T0L_N1_DBC_41
set_property -dict {PACKAGE_PIN BE31 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[15]]; # Bank 41 VCCO - VCC1V2 Net "DDR4_C0_DQS_T16" - IO_L1P_T0L_N0_DBC_41
set_property -dict {PACKAGE_PIN AP29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[40]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ40"    - IO_L23N_T3U_N9_40
set_property -dict {PACKAGE_PIN AP28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[41]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ41"    - IO_L23P_T3U_N8_40
set_property -dict {PACKAGE_PIN AL29 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[10]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C5"  - IO_L22N_T3U_N7_DBC_AD0N_40
set_property -dict {PACKAGE_PIN AL28 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[10]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T5"  - IO_L22P_T3U_N6_DBC_AD0P_40
set_property -dict {PACKAGE_PIN AN27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[42]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ42"    - IO_L24N_T3U_N11_40
set_property -dict {PACKAGE_PIN AM27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[43]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ43"    - IO_L24P_T3U_N10_40
set_property -dict {PACKAGE_PIN AR28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[47]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ47"    - IO_L21N_T3L_N5_AD8N_40
set_property -dict {PACKAGE_PIN AR27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[46]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ46"    - IO_L21P_T3L_N4_AD8P_40
set_property -dict {PACKAGE_PIN AN29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[44]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ44"    - IO_L20N_T3L_N3_AD1N_40
set_property -dict {PACKAGE_PIN AM29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[45]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ45"    - IO_L20P_T3L_N2_AD1P_40
set_property -dict {PACKAGE_PIN AT30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[11]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C14" - IO_L19N_T3L_N1_DBC_AD9N_40
set_property -dict {PACKAGE_PIN AR30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[11]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T14" - IO_L19P_T3L_N0_DBC_AD9P_40
set_property -dict {PACKAGE_PIN AV27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[49]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ49"    - IO_L17N_T2U_N9_AD10N_40
set_property -dict {PACKAGE_PIN AU27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[50]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ50"    - IO_L17P_T2U_N8_AD10P_40
set_property -dict {PACKAGE_PIN AU30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[12]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C6"  - IO_L16N_T2U_N7_QBC_AD3N_40
set_property -dict {PACKAGE_PIN AU29 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[12]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T6"  - IO_L16P_T2U_N6_QBC_AD3P_40
set_property -dict {PACKAGE_PIN AT28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[48]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ48"    - IO_L18N_T2U_N11_AD2N_40
set_property -dict {PACKAGE_PIN AT27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[51]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ51"    - IO_L18P_T2U_N10_AD2P_40
set_property -dict {PACKAGE_PIN AV29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[52]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ52"    - IO_L15N_T2L_N5_AD11N_40
set_property -dict {PACKAGE_PIN AV28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[55]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ55"    - IO_L15P_T2L_N4_AD11P_40
set_property -dict {PACKAGE_PIN AY30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[53]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ53"    - IO_L14N_T2L_N3_GC_40
set_property -dict {PACKAGE_PIN AW30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[54]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ54"    - IO_L14P_T2L_N2_GC_40
set_property -dict {PACKAGE_PIN AY28 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[13]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C15" - IO_L13N_T2L_N1_GC_QBC_40
set_property -dict {PACKAGE_PIN AY27 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[13]]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T15" - IO_L13P_T2L_N0_GC_QBC_40
set_property -dict {PACKAGE_PIN BA28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[2]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ2"     - IO_L11N_T1U_N9_GC_40
set_property -dict {PACKAGE_PIN BA27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[3]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ3"     - IO_L11P_T1U_N8_GC_40
set_property -dict {PACKAGE_PIN BB30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[0] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C0"  - IO_L10N_T1U_N7_QBC_AD4N_40
set_property -dict {PACKAGE_PIN BA30 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[0] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T0"  - IO_L10P_T1U_N6_QBC_AD4P_40
set_property -dict {PACKAGE_PIN AW29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[1]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ1"     - IO_L12N_T1U_N11_GC_40
set_property -dict {PACKAGE_PIN AW28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[0]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ0"     - IO_L12P_T1U_N10_GC_40
set_property -dict {PACKAGE_PIN BC27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[6]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ6"     - IO_L9N_T1L_N5_AD12N_40
set_property -dict {PACKAGE_PIN BB27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[7]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ7"     - IO_L9P_T1L_N4_AD12P_40
set_property -dict {PACKAGE_PIN BB29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[4]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ4"     - IO_L8N_T1L_N3_AD5N_40
set_property -dict {PACKAGE_PIN BA29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[5]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ5"     - IO_L8P_T1L_N2_AD5P_40
set_property -dict {PACKAGE_PIN BC26 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[1] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C9"  - IO_L7N_T1L_N1_QBC_AD13N_40
set_property -dict {PACKAGE_PIN BB26 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[1] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T9"  - IO_L7P_T1L_N0_QBC_AD13P_40
set_property -dict {PACKAGE_PIN BF28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[9]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ9"     - IO_L5N_T0U_N9_AD14N_40
set_property -dict {PACKAGE_PIN BE28 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[8]    ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ8"     - IO_L5P_T0U_N8_AD14P_40
set_property -dict {PACKAGE_PIN BD29 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[2] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C1"  - IO_L4N_T0U_N7_DBC_AD7N_40
set_property -dict {PACKAGE_PIN BD28 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[2] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T1"  - IO_L4P_T0U_N6_DBC_AD7P_40
set_property -dict {PACKAGE_PIN BE30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[10]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ10"    - IO_L6N_T0U_N11_AD6N_40
set_property -dict {PACKAGE_PIN BD30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[11]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ11"    - IO_L6P_T0U_N10_AD6P_40
set_property -dict {PACKAGE_PIN BF27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[12]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ12"    - IO_L3N_T0L_N5_AD15N_40
set_property -dict {PACKAGE_PIN BE27 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[13]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ13"    - IO_L3P_T0L_N4_AD15P_40
set_property -dict {PACKAGE_PIN BF30 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[14]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ14"    - IO_L2N_T0L_N3_40
set_property -dict {PACKAGE_PIN BF29 IOSTANDARD POD12_DCI      } [get_ports c0_ddr4_dq[15]   ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQ15"    - IO_L2P_T0L_N2_40
set_property -dict {PACKAGE_PIN BE26 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_c[3] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_C10" - IO_L1N_T0L_N1_DBC_40
set_property -dict {PACKAGE_PIN BD26 IOSTANDARD DIFF_POD12_DCI } [get_ports c0_ddr4_dqs_t[3] ]; # Bank 40 VCCO - VCC1V2 Net "DDR4_C0_DQS_T10" - IO_L1P_T0L_N0_DBC_40

####
### DDR4 c1
####

set_property -dict {PACKAGE_PIN AN13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[24]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ24"     - IO_L23N_T3U_N9_67
set_property -dict {PACKAGE_PIN AM13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[26]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ26"     - IO_L23P_T3U_N8_67
set_property -dict {PACKAGE_PIN AT13 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[6] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C3"   - IO_L22N_T3U_N7_DBC_AD0N_67
set_property -dict {PACKAGE_PIN AT14 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[6] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T3"   - IO_L22P_T3U_N6_DBC_AD0P_67
set_property -dict {PACKAGE_PIN AR13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[25]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ25"     - IO_L24N_T3U_N11_67
set_property -dict {PACKAGE_PIN AP13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[27]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ27"     - IO_L24P_T3U_N10_67
set_property -dict {PACKAGE_PIN AM14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[28]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ28"     - IO_L21N_T3L_N5_AD8N_67
set_property -dict {PACKAGE_PIN AL14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[30]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ30"     - IO_L21P_T3L_N4_AD8P_67
set_property -dict {PACKAGE_PIN AT15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[31]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ31"     - IO_L20N_T3L_N3_AD1N_67
set_property -dict {PACKAGE_PIN AR15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[29]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ29"     - IO_L20P_T3L_N2_AD1P_67
set_property -dict {PACKAGE_PIN AP14 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[7] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C12"  - IO_L19N_T3L_N1_DBC_AD9N_67
set_property -dict {PACKAGE_PIN AN14 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[7] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T12"  - IO_L19P_T3L_N0_DBC_AD9P_67
set_property -dict {PACKAGE_PIN AV13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[9]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ9"      - IO_L17N_T2U_N9_AD10N_67
set_property -dict {PACKAGE_PIN AU13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[8]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ8"      - IO_L17P_T2U_N8_AD10P_67
set_property -dict {PACKAGE_PIN AY15 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[2] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C1"   - IO_L16N_T2U_N7_QBC_AD3N_67
set_property -dict {PACKAGE_PIN AW15 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[2] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T1"   - IO_L16P_T2U_N6_QBC_AD3P_67
set_property -dict {PACKAGE_PIN AW13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[10]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ10"     - IO_L18N_T2U_N11_AD2N_67
set_property -dict {PACKAGE_PIN AW14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[11]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ11"     - IO_L18P_T2U_N10_AD2P_67
set_property -dict {PACKAGE_PIN AV14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[14]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ14"     - IO_L15N_T2L_N5_AD11N_67
set_property -dict {PACKAGE_PIN AU14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[12]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ12"     - IO_L15P_T2L_N4_AD11P_67
set_property -dict {PACKAGE_PIN BA11 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[15]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ15"     - IO_L14N_T2L_N3_GC_67
set_property -dict {PACKAGE_PIN AY11 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[13]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ13"     - IO_L14P_T2L_N2_GC_67
set_property -dict {PACKAGE_PIN AY12 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[3] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C10"  - IO_L13N_T2L_N1_GC_QBC_67
set_property -dict {PACKAGE_PIN AY13 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[3] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T10"  - IO_L13P_T2L_N0_GC_QBC_67
set_property -dict {PACKAGE_PIN BA13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[18]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ18"     - IO_L11N_T1U_N9_GC_67
set_property -dict {PACKAGE_PIN BA14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[19]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ19"     - IO_L11P_T1U_N8_GC_67
set_property -dict {PACKAGE_PIN BB10 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[4] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C2"   - IO_L10N_T1U_N7_QBC_AD4N_67
set_property -dict {PACKAGE_PIN BB11 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[4] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T2"   - IO_L10P_T1U_N6_QBC_AD4P_67
set_property -dict {PACKAGE_PIN BB12 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[17]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ17"     - IO_L12N_T1U_N11_GC_67
set_property -dict {PACKAGE_PIN BA12 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[16]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ16"     - IO_L12P_T1U_N10_GC_67
set_property -dict {PACKAGE_PIN BA7  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[22]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ22"     - IO_L9N_T1L_N5_AD12N_67
set_property -dict {PACKAGE_PIN BA8  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[23]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ23"     - IO_L9P_T1L_N4_AD12P_67
set_property -dict {PACKAGE_PIN BC9  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[20]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ20"     - IO_L8N_T1L_N3_AD5N_67
set_property -dict {PACKAGE_PIN BB9  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[21]   ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ21"     - IO_L8P_T1L_N2_AD5P_67
set_property -dict {PACKAGE_PIN BA9  IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[5] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C11"  - IO_L7N_T1L_N1_QBC_AD13N_67
set_property -dict {PACKAGE_PIN BA10 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[5] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T11"  - IO_L7P_T1L_N0_QBC_AD13P_67
set_property -dict {PACKAGE_PIN BD7  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[1]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ1"      - IO_L5N_T0U_N9_AD14N_67
set_property -dict {PACKAGE_PIN BC7  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[2]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ2"      - IO_L5P_T0U_N8_AD14P_67
set_property -dict {PACKAGE_PIN BF9  IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[0] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C0"   - IO_L4N_T0U_N7_DBC_AD7N_67
set_property -dict {PACKAGE_PIN BF10 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[0] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T0"   - IO_L4P_T0U_N6_DBC_AD7P_67
set_property -dict {PACKAGE_PIN BD8  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[3]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ3"      - IO_L6N_T0U_N11_AD6N_67
set_property -dict {PACKAGE_PIN BD9  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[0]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ0"      - IO_L6P_T0U_N10_AD6P_67
set_property -dict {PACKAGE_PIN BF7  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[7]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ7"      - IO_L3N_T0L_N5_AD15N_67
set_property -dict {PACKAGE_PIN BE7  IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[6]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ6"      - IO_L3P_T0L_N4_AD15P_67
set_property -dict {PACKAGE_PIN BE10 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[5]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ5"      - IO_L2N_T0L_N3_67
set_property -dict {PACKAGE_PIN BD10 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[4]    ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQ4"      - IO_L2P_T0L_N2_67
set_property -dict {PACKAGE_PIN BF8  IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[1] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_C9"   - IO_L1N_T0L_N1_DBC_67
set_property -dict {PACKAGE_PIN BE8  IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[1] ]; # Bank 67 VCCO - VCC1V2 Net "DDR4_C1_DQS_T9"   - IO_L1P_T0L_N0_DBC_67
set_property -dict {PACKAGE_PIN AM15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[56]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ56"     - IO_L23N_T3U_N9_66
set_property -dict {PACKAGE_PIN AL15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[57]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ57"     - IO_L23P_T3U_N8_66
set_property -dict {PACKAGE_PIN AR16 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[14]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C7"   - IO_L22N_T3U_N7_DBC_AD0N_66
set_property -dict {PACKAGE_PIN AP16 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[14]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T7"   - IO_L22P_T3U_N6_DBC_AD0P_66
#set_property -dict {PACKAGE_PIN AN18 IOSTANDARD LVCMOS12       } [get_ports c1_ddr4_event_n  ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_EVENT_B"  - IO_T3U_N12_66
set_property -dict {PACKAGE_PIN AN16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[59]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ59"     - IO_L24N_T3U_N11_66
set_property -dict {PACKAGE_PIN AN17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[58]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ58"     - IO_L24P_T3U_N10_66
set_property -dict {PACKAGE_PIN AL16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[63]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ63"     - IO_L21N_T3L_N5_AD8N_66
set_property -dict {PACKAGE_PIN AL17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[62]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ62"     - IO_L21P_T3L_N4_AD8P_66
set_property -dict {PACKAGE_PIN AR18 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[60]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ60"     - IO_L20N_T3L_N3_AD1N_66
set_property -dict {PACKAGE_PIN AP18 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[61]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ61"     - IO_L20P_T3L_N2_AD1P_66
set_property -dict {PACKAGE_PIN AM16 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[15]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C16"  - IO_L19N_T3L_N1_DBC_AD9N_66
set_property -dict {PACKAGE_PIN AM17 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[15]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T16"  - IO_L19P_T3L_N0_DBC_AD9P_66
set_property -dict {PACKAGE_PIN AU16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[50]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ50"     - IO_L17N_T2U_N9_AD10N_66
set_property -dict {PACKAGE_PIN AU17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[51]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ51"     - IO_L17P_T2U_N8_AD10P_66
set_property -dict {PACKAGE_PIN AW18 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[12]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C6"   - IO_L16N_T2U_N7_QBC_AD3N_66
set_property -dict {PACKAGE_PIN AV18 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[12]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T6"   - IO_L16P_T2U_N6_QBC_AD3P_66
set_property -dict {PACKAGE_PIN AR17 IOSTANDARD LVCMOS12       } [get_ports c1_ddr4_reset_n  ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_RESET_N"  - IO_T2U_N12_66
set_property -dict {PACKAGE_PIN AV16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[48]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ48"     - IO_L18N_T2U_N11_AD2N_66
set_property -dict {PACKAGE_PIN AV17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[49]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ49"     - IO_L18P_T2U_N10_AD2P_66
set_property -dict {PACKAGE_PIN AT17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[55]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ55"     - IO_L15N_T2L_N5_AD11N_66
set_property -dict {PACKAGE_PIN AT18 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[54]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ54"     - IO_L15P_T2L_N4_AD11P_66
set_property -dict {PACKAGE_PIN BB16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[53]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ53"     - IO_L14N_T2L_N3_GC_66
set_property -dict {PACKAGE_PIN BB17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[52]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ52"     - IO_L14P_T2L_N2_GC_66
set_property -dict {PACKAGE_PIN AY16 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[13]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C15"  - IO_L13N_T2L_N1_GC_QBC_66
set_property -dict {PACKAGE_PIN AW16 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[13]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T15"  - IO_L13P_T2L_N0_GC_QBC_66
set_property -dict {PACKAGE_PIN AY17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[40]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ40"     - IO_L11N_T1U_N9_GC_66
set_property -dict {PACKAGE_PIN AY18 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[42]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ42"     - IO_L11P_T1U_N8_GC_66
set_property -dict {PACKAGE_PIN BC12 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[10]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C5"   - IO_L10N_T1U_N7_QBC_AD4N_66
set_property -dict {PACKAGE_PIN BC13 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[10]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T5"   - IO_L10P_T1U_N6_QBC_AD4P_66
set_property -dict {PACKAGE_PIN BA17 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[41]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ41"     - IO_L12N_T1U_N11_GC_66
set_property -dict {PACKAGE_PIN BA18 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[43]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ43"     - IO_L12P_T1U_N10_GC_66
set_property -dict {PACKAGE_PIN BB15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[45]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ45"     - IO_L9N_T1L_N5_AD12N_66
set_property -dict {PACKAGE_PIN BA15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[44]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ44"     - IO_L9P_T1L_N4_AD12P_66
set_property -dict {PACKAGE_PIN BD11 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[47]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ47"     - IO_L8N_T1L_N3_AD5N_66
set_property -dict {PACKAGE_PIN BC11 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[46]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ46"     - IO_L8P_T1L_N2_AD5P_66
set_property -dict {PACKAGE_PIN BC14 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[11]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C14"  - IO_L7N_T1L_N1_QBC_AD13N_66
set_property -dict {PACKAGE_PIN BB14 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[11]]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T14"  - IO_L7P_T1L_N0_QBC_AD13P_66
set_property -dict {PACKAGE_PIN BD13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[35]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ35"     - IO_L5N_T0U_N9_AD14N_66
set_property -dict {PACKAGE_PIN BD14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[33]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ33"     - IO_L5P_T0U_N8_AD14P_66
set_property -dict {PACKAGE_PIN BE11 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[8] ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C4"   - IO_L4N_T0U_N7_DBC_AD7N_66
set_property -dict {PACKAGE_PIN BE12 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[8] ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T4"   - IO_L4P_T0U_N6_DBC_AD7P_66
set_property -dict {PACKAGE_PIN BF12 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[34]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ34"     - IO_L6N_T0U_N11_AD6N_66
set_property -dict {PACKAGE_PIN BE13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[32]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ32"     - IO_L6P_T0U_N10_AD6P_66
set_property -dict {PACKAGE_PIN BD15 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[36]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ36"     - IO_L3N_T0L_N5_AD15N_66
set_property -dict {PACKAGE_PIN BD16 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[37]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ37"     - IO_L3P_T0L_N4_AD15P_66
set_property -dict {PACKAGE_PIN BF13 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[39]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ39"     - IO_L2N_T0L_N3_66
set_property -dict {PACKAGE_PIN BF14 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[38]   ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQ38"     - IO_L2P_T0L_N2_66
set_property -dict {PACKAGE_PIN BF15 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[9] ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_C13"  - IO_L1N_T0L_N1_DBC_66
set_property -dict {PACKAGE_PIN BE15 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[9] ]; # Bank 66 VCCO - VCC1V2 Net "DDR4_C1_DQS_T13"  - IO_L1P_T0L_N0_DBC_66
set_property -dict {PACKAGE_PIN AM25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[15]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR15"    - IO_L22N_T3U_N7_DBC_AD0N_D05_65
set_property -dict {PACKAGE_PIN AL25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[14]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR14"    - IO_L22P_T3U_N6_DBC_AD0P_D04_65
set_property -dict {PACKAGE_PIN AP26 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_ba[1]    ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_BA1"      - IO_T3U_N12_PERSTN0_65
set_property -dict {PACKAGE_PIN AN26 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[3]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR3"     - IO_L24N_T3U_N11_DOUT_CSO_B_65
set_property -dict {PACKAGE_PIN AM26 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[10]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR10"    - IO_L24P_T3U_N10_EMCCLK_65
#set_property -dict {PACKAGE_PIN AP24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_odt[1]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ODT1"     - IO_L21N_T3L_N5_AD8N_D07_65
#set_property -dict {PACKAGE_PIN AP23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cs_n[3]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CS_B3"    - IO_L21P_T3L_N4_AD8P_D06_65
#set_property -dict {PACKAGE_PIN AM24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[17]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR17"    - IO_L20N_T3L_N3_AD1N_D09_65
set_property -dict {PACKAGE_PIN AL24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[13]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR13"    - IO_L20P_T3L_N2_AD1P_D08_65
set_property -dict {PACKAGE_PIN AN24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[0]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR0"     - IO_L19N_T3L_N1_DBC_AD9N_D11_65
set_property -dict {PACKAGE_PIN AN23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[16]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR16"    - IO_L19P_T3L_N0_DBC_AD9P_D10_65
#set_property -dict {PACKAGE_PIN AV26 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c1_ddr4_ck_c[1]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CK_C1"    - IO_L17N_T2U_N9_AD10N_D15_65
#set_property -dict {PACKAGE_PIN AU26 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c1_ddr4_ck_t[1]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CK_T1"    - IO_L17P_T2U_N8_AD10P_D14_65
set_property -dict {PACKAGE_PIN AT23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_par   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_PAR"      - IO_L16N_T2U_N7_QBC_AD3N_A01_D17_65
#set_property -dict {PACKAGE_PIN AR23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cs_n[2]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CS_B2"    - IO_L16P_T2U_N6_QBC_AD3P_A00_D16_65
#set_property -dict {PACKAGE_PIN AP25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cs_n[1]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CS_B1"    - IO_T2U_N12_CSI_ADV_B_65
set_property -dict {PACKAGE_PIN AU24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_ba[0]    ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_BA0"      - IO_L18N_T2U_N11_AD2N_D13_65
set_property -dict {PACKAGE_PIN AT24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[1]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR1"     - IO_L18P_T2U_N10_AD2P_D12_65
set_property -dict {PACKAGE_PIN AU25 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c1_ddr4_ck_c[0]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CK_C0"    - IO_L15N_T2L_N5_AD11N_A03_D19_65
set_property -dict {PACKAGE_PIN AT25 IOSTANDARD DIFF_SSTL12_DCI} [get_ports c1_ddr4_ck_t[0]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CK_T0"    - IO_L15P_T2L_N4_AD11P_A02_D18_65
set_property -dict {PACKAGE_PIN AV24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[6]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR6"     - IO_L14N_T2L_N3_GC_A05_D21_65
set_property -dict {PACKAGE_PIN AV23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cs_n[0]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CS_B0"    - IO_L14P_T2L_N2_GC_A04_D20_65
set_property -dict {PACKAGE_PIN AW26 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_bg[1]    ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_BG1"      - IO_L13N_T2L_N1_GC_QBC_A07_D23_65
set_property -dict {PACKAGE_PIN AW25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_act_n    ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ACT_B"    - IO_L13P_T2L_N0_GC_QBC_A06_D22_65
set_property -dict {PACKAGE_PIN AY26 IOSTANDARD LVCMOS12       } [get_ports c1_ddr4_alert_n  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ALERT_B"  - IO_L11N_T1U_N9_GC_A11_D27_65
set_property -dict {PACKAGE_PIN AY25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[8]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR8"     - IO_L11P_T1U_N8_GC_A10_D26_65
set_property -dict {PACKAGE_PIN AY23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[5]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR5"     - IO_L10N_T1U_N7_QBC_AD4N_A13_D29_65
set_property -dict {PACKAGE_PIN AY22 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[4]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR4"     - IO_L10P_T1U_N6_QBC_AD4P_A12_D28_65
set_property -dict {PACKAGE_PIN BA25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[11]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR11"    - IO_T1U_N12_SMBALERT_65
set_property -dict {PACKAGE_PIN AW24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[2]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR2"     - IO_L12N_T1U_N11_GC_A09_D25_65
set_property -dict {PACKAGE_PIN AW23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_odt[0]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ODT0"     - IO_L12P_T1U_N10_GC_A08_D24_65
set_property -dict {PACKAGE_PIN BB25 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cke[0]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CKE0"     - IO_L9N_T1L_N5_AD12N_A15_D31_65
#set_property -dict {PACKAGE_PIN BB24 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_cke[1]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_CKE1"     - IO_L9P_T1L_N4_AD12P_A14_D30_65
set_property -dict {PACKAGE_PIN BA23 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[9]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR9"     - IO_L8N_T1L_N3_AD5N_A17_65
set_property -dict {PACKAGE_PIN BA22 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[7]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR7"     - IO_L8P_T1L_N2_AD5P_A16_65
set_property -dict {PACKAGE_PIN BC22 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_bg[0]    ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_BG0"      - IO_L7N_T1L_N1_QBC_AD13N_A19_65
set_property -dict {PACKAGE_PIN BB22 IOSTANDARD SSTL12_DCI     } [get_ports c1_ddr4_adr[12]  ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_ADR12"    - IO_L7P_T1L_N0_QBC_AD13P_A18_65
set_property -dict {PACKAGE_PIN BF25 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[64]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ64"     - IO_L5N_T0U_N9_AD14N_A23_65
set_property -dict {PACKAGE_PIN BF24 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[65]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ65"     - IO_L5P_T0U_N8_AD14P_A22_65
set_property -dict {PACKAGE_PIN BD24 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[16]]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQS_C8"   - IO_L4N_T0U_N7_DBC_AD7N_A25_65
set_property -dict {PACKAGE_PIN BC24 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[16]]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQS_T8"   - IO_L4P_T0U_N6_DBC_AD7P_A24_65
set_property -dict {PACKAGE_PIN BE25 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[67]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ67"     - IO_L6N_T0U_N11_AD6N_A21_65
set_property -dict {PACKAGE_PIN BD25 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[66]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ66"     - IO_L6P_T0U_N10_AD6P_A20_65
set_property -dict {PACKAGE_PIN BF23 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[70]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ70"     - IO_L3N_T0L_N5_AD15N_A27_65
set_property -dict {PACKAGE_PIN BE23 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[71]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ71"     - IO_L3P_T0L_N4_AD15P_A26_65
set_property -dict {PACKAGE_PIN BD23 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[68]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ68"     - IO_L2N_T0L_N3_FWE_FCS2_B_65
set_property -dict {PACKAGE_PIN BC23 IOSTANDARD POD12_DCI      } [get_ports c1_ddr4_dq[69]   ]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQ69"     - IO_L2P_T0L_N2_FOE_B_65
set_property -dict {PACKAGE_PIN BF22 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_c[17]]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQS_C17"  - IO_L1N_T0L_N1_DBC_RS1_65
set_property -dict {PACKAGE_PIN BE22 IOSTANDARD DIFF_POD12_DCI } [get_ports c1_ddr4_dqs_t[17]]; # Bank 65 VCCO - VCC1V2 Net "DDR4_C1_DQS_T17"  - IO_L1P_T0L_N0_DBC_RS0_65

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
set_property -dict {PACKAGE_PIN G15  IOSTANDARD LVCMOS12       } [get_ports c3_ddr4_alert_n  ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_ALERT_B"  - IO_L11N_T1U_N9_GC_70
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
set_property -dict {PACKAGE_PIN N13  IOSTANDARD SSTL12_DCI     } [get_ports c3_ddr4_dq[66]   ]; # Bank 70  VCCO - VCC1V2 Net "DDR4_C3_DQ66"     - IO_L5N_T0U_N9_AD14N_70
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