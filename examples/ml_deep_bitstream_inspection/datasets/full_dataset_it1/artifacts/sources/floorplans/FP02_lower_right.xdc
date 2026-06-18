# FP02_lower_right — Lower region shifted to right columns (X2-X5)
# Upper: X0Y7:X5Y10 (full width), Lower: X2Y0:X5Y6 (right columns)
# 52 clock regions (same as FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y10 CLOCKREGION_X2Y0:CLOCKREGION_X5Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
