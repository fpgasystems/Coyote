create_pblock pblock_inst_shell
add_cells_to_pblock [get_pblocks pblock_inst_shell] [get_cells -quiet [list inst_shell]]
resize_pblock [get_pblocks pblock_inst_shell] -add {SLICE_X117Y660:SLICE_X232Y719 SLICE_X117Y180:SLICE_X175Y239 SLICE_X176Y0:SLICE_X232Y59}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_HBM_APB_INTF_X25Y0:BLI_HBM_APB_INTF_X31Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_HBM_AXI_INTF_X25Y0:BLI_HBM_AXI_INTF_X31Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_X1Y264:BUFG_GT_X1Y287}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_SYNC_X1Y165:BUFG_GT_SYNC_X1Y179}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP48E2_X16Y258:DSP48E2_X31Y281 DSP48E2_X25Y0:DSP48E2_X31Y17 DSP48E2_X16Y66:DSP48E2_X24Y89}
resize_pblock [get_pblocks pblock_inst_shell] -add {HPIOB_DCI_SNGL_X0Y0:HPIOB_DCI_SNGL_X0Y3}
resize_pblock [get_pblocks pblock_inst_shell] -add {HPIO_RCLK_PRBS_X0Y0:HPIO_RCLK_PRBS_X0Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {LAGUNA_X16Y480:LAGUNA_X31Y599 LAGUNA_X16Y0:LAGUNA_X23Y119}
resize_pblock [get_pblocks pblock_inst_shell] -add {PCIE4CE4_X1Y0:PCIE4CE4_X1Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB18_X8Y264:RAMB18_X13Y287 RAMB18_X11Y0:RAMB18_X13Y23 RAMB18_X8Y72:RAMB18_X10Y95}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB36_X8Y132:RAMB36_X13Y143 RAMB36_X11Y0:RAMB36_X13Y11 RAMB36_X8Y36:RAMB36_X10Y47}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM288_X2Y176:URAM288_X4Y191 URAM288_X4Y0:URAM288_X4Y15 URAM288_X2Y48:URAM288_X3Y63}
resize_pblock [get_pblocks pblock_inst_shell] -add {CLOCKREGION_X0Y11:CLOCKREGION_X3Y11 CLOCKREGION_X0Y6:CLOCKREGION_X7Y10 CLOCKREGION_X0Y4:CLOCKREGION_X5Y5 CLOCKREGION_X0Y3:CLOCKREGION_X3Y3 CLOCKREGION_X0Y0:CLOCKREGION_X5Y2}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_shell]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_shell]