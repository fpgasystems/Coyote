# This is an example floorplan for the V80 device; similar floorplans can be created for other devices
# For more detail on how to create a floorplan from the Vivado GUI, check out Vivado Design Suite User Guide: Dynamic Function eXchange (UG909)

# NOTE: Vivado recommends making the programmable region pblock non-aligned to a clock region boundary, as done below with the additional resize commands

create_pblock pblock_inst_user_wrapper_0
add_cells_to_pblock [get_pblocks pblock_inst_user_wrapper_0] [get_cells -quiet [list inst_shell/inst_dynamic/inst_user_wrapper_0]]
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {SLICE_X204Y192:SLICE_X323Y383}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {DSP58_CPLX_X6Y96:DSP58_CPLX_X11Y191}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {DSP_X12Y96:DSP_X23Y191}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {RAMB18_X9Y98:RAMB18_X13Y193}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {RAMB36_X9Y49:RAMB36_X13Y96}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {URAM288_X5Y49:URAM288_X7Y96}
resize_pblock [get_pblocks pblock_inst_user_wrapper_0] -add {URAM_CAS_DLY_X5Y2:URAM_CAS_DLY_X7Y3}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_user_wrapper_0]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_user_wrapper_0]