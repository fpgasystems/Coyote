# FP13_upper_top_plus_lower_right — Combined upper-top + lower-right trim
# Upper: X0Y7:X5Y9 (top row Y10 removed), Lower: X0Y0:X2Y6 (right column X3 removed)
# 39 clock regions (75.0% of FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y9 CLOCKREGION_X0Y0:CLOCKREGION_X2Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
