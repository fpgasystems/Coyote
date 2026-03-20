# FP05_wide_upper — Shifted vertical split of U55C user area
# Upper rows Y8-Y10 full width + lower rows Y0-Y7 partial width X0-X2

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {CLOCKREGION_X0Y8:CLOCKREGION_X5Y10 CLOCKREGION_X0Y0:CLOCKREGION_X2Y7}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]
