create_pblock pblock_inst_shell
add_cells_to_pblock [get_pblocks pblock_inst_shell] [get_cells -quiet [list inst_shell]]
resize_pblock [get_pblocks pblock_inst_shell] -add {SLICE_X117Y180:SLICE_X175Y539}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP48E2_X16Y72:DSP48E2_X24Y215}
resize_pblock [get_pblocks pblock_inst_shell] -add {IOB_X0Y156:IOB_X0Y415}
resize_pblock [get_pblocks pblock_inst_shell] -add {LAGUNA_X16Y120:LAGUNA_X23Y599}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB18_X8Y72:RAMB18_X10Y215}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB36_X8Y36:RAMB36_X10Y107}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM288_X2Y48:URAM288_X3Y143}
resize_pblock [get_pblocks pblock_inst_shell] -add {CLOCKREGION_X0Y9:CLOCKREGION_X7Y15 CLOCKREGION_X0Y3:CLOCKREGION_X3Y8 CLOCKREGION_X0Y0:CLOCKREGION_X7Y2}
set_property CONTAIN_ROUTING 1 [get_pblocks pblock_inst_shell]
set_property EXCLUDE_PLACEMENT 1 [get_pblocks pblock_inst_shell]
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_shell]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_shell]