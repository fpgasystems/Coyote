# FP08_lower_right_trim - Lower region trimmed on right (X0-X2)
# Upper: X0Y7:X5Y10 (same as FP00), Lower: X0Y0:X2Y6 (right column X3 removed)
# 45 clock regions (86.5% of FP00)
# NOTE: Column trimming of lower region caused routing congestion in it1 (FP01/FP02).
# Monitor timing on high-RO standalone designs.

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y10 CLOCKREGION_X0Y0:CLOCKREGION_X2Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
