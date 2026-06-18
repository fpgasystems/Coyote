# FP07_lower_left_trim — Lower region trimmed on left (X1-X3)
# Upper: X0Y7:X5Y10 (same as FP00), Lower: X1Y0:X3Y6 (left column X0 removed)
# 45 clock regions (86.5% of FP00)
# NOTE: Column trimming of lower region caused routing congestion in it1 (FP01/FP02).
# Monitor timing on high-RO standalone designs.

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y10 CLOCKREGION_X1Y0:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
