# FP03_upper_left_trim — Upper region trimmed on left (X1-X5)
# Upper: X1Y7:X5Y10 (left column removed), Lower: X0Y0:X3Y6 (same as FP00)
# 48 clock regions (92.3% of FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X1Y7:CLOCKREGION_X5Y10 CLOCKREGION_X0Y0:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
