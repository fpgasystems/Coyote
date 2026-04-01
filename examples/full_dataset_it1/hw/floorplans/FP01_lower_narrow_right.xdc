# FP01_lower_trim_bottom — Lower region trimmed at bottom (Y1-Y6), full upper
# 48 clock regions (92.3% of FP00)
# Redesigned 2026-03-28: previous 45-CR version (X0-X2 lower) caused routing
# congestion for STAND RO-heavy designs. Now trims a row instead of a column
# to keep full 4-column lower width. Old version saved in BENIGN_FP01/floorplan_used.xdc.

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y7:CLOCKREGION_X5Y10 CLOCKREGION_X0Y1:CLOCKREGION_X3Y6}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
