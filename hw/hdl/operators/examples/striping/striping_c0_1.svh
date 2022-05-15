// Tie-off
always_comb axi_ctrl.tie_off_s();

// I/O
AXI4S axis_sink_int ();
AXI4S axis_src_int ();

axis_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_sink), .m_axis(axis_sink_int));
axis_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_card_src));

// UL
always_comb begin
    axis_src_int.tvalid  = axis_sink_int.tvalid;
    for(int i = 0; i < 16; i++)
        axis_src_int.tdata[i*32+:32] = axis_sink_int.tdata[i*32+:32] + 1; 
    axis_src_int.tkeep   = axis_sink_int.tkeep;
    axis_src_int.tlast   = axis_sink_int.tlast;
    
    axis_sink_int.tready = axis_src_int.tready;
end
