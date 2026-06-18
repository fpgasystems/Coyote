# FP12_upper_bottom_plus_lower_left — Combined upper-bottom + lower-left trim
# Upper: X0Y8:X5Y10 (bottom row Y7 removed), Lower: X1Y0:X3Y6 (left column X0 removed)
# 39 clock regions (75.0% of FP00)

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y8:CLOCKREGION_X5Y10 CLOCKREGION_X1Y0:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
