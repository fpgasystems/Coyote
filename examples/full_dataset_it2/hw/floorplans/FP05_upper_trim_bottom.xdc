# FP05_upper_trim_bottom — Upper region trimmed at bottom (Y8-Y10)
# Upper: X0Y8:X5Y10 (row Y7 removed), Lower: X0Y0:X3Y6 (same as FP00)
# 46 clock regions (88.5% of FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y8:CLOCKREGION_X5Y10 CLOCKREGION_X0Y0:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
