create_pblock pblock_inst_shell
add_cells_to_pblock [get_pblocks pblock_inst_shell] [get_cells -quiet [list inst_shell]]
resize_pblock [get_pblocks pblock_inst_shell] -add {SLICE_X164Y188:SLICE_X203Y331 SLICE_X144Y0:SLICE_X163Y331 SLICE_X0Y428:SLICE_X27Y903}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP0_X84Y0:BLI_A_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP1_X84Y0:BLI_A_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP2_X84Y0:BLI_A_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP0_X84Y0:BLI_B_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP1_X84Y0:BLI_B_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP2_X84Y0:BLI_B_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP0_X84Y0:BLI_C_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP1_X84Y0:BLI_C_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP2_X84Y0:BLI_C_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP4_X84Y0:BLI_D_GRP4_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP5_X84Y0:BLI_D_GRP5_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP6_X84Y0:BLI_D_GRP6_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP7_X84Y0:BLI_D_GRP7_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_FABRIC_X2Y48:BUFG_FABRIC_X2Y95}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_X0Y120:BUFG_GT_X0Y239}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_SYNC_X0Y205:BUFG_GT_SYNC_X0Y409}
resize_pblock [get_pblocks pblock_inst_shell] -add {DCMAC_X0Y2:DCMAC_X0Y2}
resize_pblock [get_pblocks pblock_inst_shell] -add {DPLL_X0Y10:DPLL_X0Y19}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP58_CPLX_X3Y94:DSP58_CPLX_X5Y165 DSP58_CPLX_X3Y0:DSP58_CPLX_X3Y93}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP_X6Y94:DSP_X11Y165 DSP_X6Y0:DSP_X7Y93}
resize_pblock [get_pblocks pblock_inst_shell] -add {GTM_QUAD_X0Y9:GTM_QUAD_X0Y10}
resize_pblock [get_pblocks pblock_inst_shell] -add {GTM_REFCLK_X0Y18:GTM_REFCLK_X0Y21}
resize_pblock [get_pblocks pblock_inst_shell] -add {HBM_MC_X15Y0:HBM_MC_X15Y0 HBM_MC_X0Y0:HBM_MC_X1Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {HBM_PHY_CHNL_X15Y0:HBM_PHY_CHNL_X15Y0 HBM_PHY_CHNL_X0Y0:HBM_PHY_CHNL_X1Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {IRI_QUAD_X0Y3660:IRI_QUAD_X17Y3671 IRI_QUAD_X1Y3648:IRI_QUAD_X16Y3659 IRI_QUAD_X0Y2892:IRI_QUAD_X17Y3647 IRI_QUAD_X0Y1740:IRI_QUAD_X3Y2507 IRI_QUAD_X92Y780:IRI_QUAD_X134Y1355 IRI_QUAD_X92Y16:IRI_QUAD_X106Y779 IRI_QUAD_X94Y4:IRI_QUAD_X105Y15 IRI_QUAD_X92Y0:IRI_QUAD_X106Y3}
resize_pblock [get_pblocks pblock_inst_shell] -add {MRMAC_X0Y2:MRMAC_X0Y4}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NMU512_X1Y4:NOC_NMU512_X1Y6}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NMU_HBM2E_X61Y0:NOC_NMU_HBM2E_X63Y0 NOC_NMU_HBM2E_X0Y0:NOC_NMU_HBM2E_X5Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NPS_VNOC_X1Y8:NOC_NPS_VNOC_X1Y13}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NSU512_X1Y4:NOC_NSU512_X1Y6}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB18_X6Y96:RAMB18_X7Y167 RAMB18_X5Y2:RAMB18_X5Y167 RAMB18_X0Y216:RAMB18_X0Y455}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB36_X6Y48:RAMB36_X7Y83 RAMB36_X5Y1:RAMB36_X5Y83 RAMB36_X0Y108:RAMB36_X0Y227}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM288_X3Y48:URAM288_X4Y83 URAM288_X3Y1:URAM288_X3Y47}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM_CAS_DLY_X3Y2:URAM_CAS_DLY_X4Y3 URAM_CAS_DLY_X3Y0:URAM_CAS_DLY_X3Y1}
resize_pblock [get_pblocks pblock_inst_shell] -add {CLOCKREGION_X1Y11:CLOCKREGION_X7Y11 CLOCKREGION_X1Y7:CLOCKREGION_X8Y10 CLOCKREGION_X1Y5:CLOCKREGION_X9Y6 CLOCKREGION_X5Y3:CLOCKREGION_X9Y4 CLOCKREGION_X4Y1:CLOCKREGION_X8Y2 CLOCKREGION_X5Y0:CLOCKREGION_X10Y0}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_shell]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_shell]