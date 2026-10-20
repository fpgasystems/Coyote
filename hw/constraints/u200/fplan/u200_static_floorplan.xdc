create_pblock pblock_inst_shell
add_cells_to_pblock [get_pblocks pblock_inst_shell] [get_cells -quiet [list inst_shell]]
resize_pblock [get_pblocks pblock_inst_shell] -add {SLICE_X88Y240:SLICE_X121Y659}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP48E2_X11Y96:DSP48E2_X14Y263}
resize_pblock [get_pblocks pblock_inst_shell] -add {IOB_X1Y208:IOB_X1Y519}
resize_pblock [get_pblocks pblock_inst_shell] -add {LAGUNA_X12Y120:LAGUNA_X16Y599}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB18_X7Y96:RAMB18_X8Y263}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB36_X7Y48:RAMB36_X8Y131}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM288_X2Y64:URAM288_X3Y175}
resize_pblock [get_pblocks pblock_inst_shell] -add {CLOCKREGION_X0Y11:CLOCKREGION_X5Y14 CLOCKREGION_X0Y4:CLOCKREGION_X2Y10 CLOCKREGION_X0Y0:CLOCKREGION_X5Y3}
set_property CONTAIN_ROUTING 1 [get_pblocks pblock_inst_shell]
set_property EXCLUDE_PLACEMENT 1 [get_pblocks pblock_inst_shell]
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_shell]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_shell]