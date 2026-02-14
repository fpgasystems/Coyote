if {$cfg(fpga_arch) eq "ultrascale_plus"} {
    # Debug Bridges for UltraScale+ devices
    create_ip -name debug_bridge -vendor xilinx.com -library ip -version 3.0 -module_name debug_bridge_user
    set_property -dict [list CONFIG.C_DEBUG_MODE {1} CONFIG.C_NUM_BS_MASTER {0} CONFIG.C_DESIGN_TYPE {1}] [get_ips debug_bridge_user]
} elseif {$cfg(fpga_arch) eq "versal"} {
    # Debug Hub for Versal devices
    proc cr_bd_design_dbg_hub_user { } {
        upvar #0 cfg cnfg

        create_bd_design "debug_hub_user"

        set axi_debug_hub [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_debug_hub ]
        set_property -dict [ list \
            CONFIG.ADDR_WIDTH {64} \
            CONFIG.DATA_WIDTH {128} \
            CONFIG.ID_WIDTH {2} \
            CONFIG.PROTOCOL {AXI4} \
        ] $axi_debug_hub

        set dresetn [ create_bd_port -dir I -type rst dresetn ]

        set dclk [ create_bd_port -dir I -type clk dclk ]  
        set cmd "set_property -dict \[ list \
            CONFIG.FREQ_HZ $cnfg(sclk_f)000000 \
            CONFIG.ASSOCIATED_BUSIF {axi_debug_hub} \
            CONFIG.ASSOCIATED_RESET {dresetn} \
        ] \$dclk"
        eval $cmd
    
        set axi_dbg_hub_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dbg_hub:2.0 axi_dbg_hub_0 ]

        connect_bd_intf_net [get_bd_intf_ports axi_debug_hub] [get_bd_intf_pins axi_dbg_hub_0/S_AXI]
        connect_bd_net [get_bd_ports dclk] [get_bd_pins axi_dbg_hub_0/aclk]
        connect_bd_net [get_bd_ports dresetn] [get_bd_pins axi_dbg_hub_0/aresetn]

        assign_bd_address -offset 0x020240000000 -range 2M -target_address_space [get_bd_addr_spaces axi_debug_hub] [get_bd_addr_segs axi_dbg_hub_0/S_AXI_DBG_HUB/Mem0] -force

        validate_bd_design
        save_bd_design
        close_bd_design "debug_hub_user"

        return 0
    }

    cr_bd_design_dbg_hub_user
}
