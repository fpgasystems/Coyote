# FP14_upper_inner_band — Upper region trimmed on both outer columns
# Upper: X1Y7:X4Y10 (outer columns X0 and X5 removed), Lower: X0Y0:X3Y6 (same as FP00)
# 44 clock regions (84.6% of FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X1Y7:CLOCKREGION_X4Y10 CLOCKREGION_X0Y0:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
