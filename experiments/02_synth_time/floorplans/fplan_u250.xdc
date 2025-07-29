create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]

resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {SLICE_X38Y480:SLICE_X120Y535 SLICE_X61Y394:SLICE_X120Y479}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {BUFGCE_X0Y191:BUFGCE_X0Y208}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {BUFGCE_DIV_X0Y31:BUFGCE_DIV_X0Y34}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {DSP48E2_X9Y158:DSP48E2_X15Y213 DSP48E2_X5Y192:DSP48E2_X8Y213}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {IOB_X0Y364:IOB_X0Y441}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {LAGUNA_X8Y360:LAGUNA_X15Y591 LAGUNA_X6Y480:LAGUNA_X7Y591}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {MMCM_X0Y7:MMCM_X0Y8}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {RAMB18_X5Y158:RAMB18_X8Y213 RAMB18_X3Y192:RAMB18_X4Y213}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {RAMB36_X5Y79:RAMB36_X8Y106 RAMB36_X3Y96:RAMB36_X4Y106}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {URAM288_X1Y108:URAM288_X1Y139 URAM288_X0Y128:URAM288_X0Y139}

set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]