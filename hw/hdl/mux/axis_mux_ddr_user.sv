import lynxTypes::*;

/**
 * Multi channel data multiplexer - user signals
 */
module axis_mux_ddr_user (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4S.s                                 axis_in_user,
    AXI4S.m                                 axis_out_user,

    AXI4S.m                                 axis_out_card [N_DDR_CHAN],
    AXI4S.s                                 axis_in_card [N_DDR_CHAN]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// interface loop issues => temp signals
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                             axis_in_user_tvalid;
logic                                             axis_in_user_tready;
logic [N_DDR_CHAN*AXI_DATA_BITS-1:0]              axis_in_user_tdata;
logic [N_DDR_CHAN*AXI_DATA_BITS/8-1:0]            axis_in_user_tkeep;
logic                                             axis_in_user_tlast;

logic                                             axis_out_user_tvalid;
logic                                             axis_out_user_tready;
logic [N_DDR_CHAN*AXI_DATA_BITS-1:0]              axis_out_user_tdata;
logic [N_DDR_CHAN*AXI_DATA_BITS/8-1:0]            axis_out_user_tkeep;
logic                                             axis_out_user_tlast;

logic [N_DDR_CHAN-1:0]                            axis_fifo_sink_tvalid;
logic [N_DDR_CHAN-1:0]                            axis_fifo_sink_tready;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS-1:0]         axis_fifo_sink_tdata;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS/8-1:0]       axis_fifo_sink_tkeep;
logic [N_DDR_CHAN-1:0]                            axis_fifo_sink_tlast;

logic [N_DDR_CHAN-1:0]                            axis_fifo_src_tvalid;
logic [N_DDR_CHAN-1:0]                            axis_fifo_src_tready;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS-1:0]         axis_fifo_src_tdata;
logic [N_DDR_CHAN-1:0][AXI_DATA_BITS/8-1:0]       axis_fifo_src_tkeep;
logic [N_DDR_CHAN-1:0]                            axis_fifo_src_tlast;

assign axis_in_user_tvalid = axis_in_user.tvalid;
assign axis_in_user_tkeep  = axis_in_user.tkeep;
assign axis_in_user_tdata  = axis_in_user.tdata;
assign axis_in_user_tlast  = axis_in_user.tlast;
assign axis_in_user.tready = axis_in_user_tready;

assign axis_out_user.tvalid = axis_out_user_tvalid;
assign axis_out_user.tdata  = axis_out_user_tdata;
assign axis_out_user.tkeep  = axis_out_user_tkeep;
assign axis_out_user.tlast  = axis_out_user_tlast;
assign axis_out_user_tready = axis_out_user.tready;

for(genvar i = 0; i < N_DDR_CHAN; i++) begin
  axis_data_fifo_512 inst_fifo_ddr_sink_mux (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_fifo_sink_tvalid[i]),
        .s_axis_tready(axis_fifo_sink_tready[i]),
        .s_axis_tdata(axis_fifo_sink_tdata[i]),
        .s_axis_tkeep(axis_fifo_sink_tkeep[i]),
        .s_axis_tlast(axis_fifo_sink_tlast[i]),
        .m_axis_tvalid(axis_out_card[i].tvalid),
        .m_axis_tready(axis_out_card[i].tready),
        .m_axis_tdata(axis_out_card[i].tdata),
        .m_axis_tkeep(axis_out_card[i].tkeep),
        .m_axis_tlast(axis_out_card[i].tlast)
    );
    
   axis_data_fifo_512 inst_fifo_ddr_src_mux (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_in_card[i].tvalid),
        .s_axis_tready(axis_in_card[i].tready),
        .s_axis_tdata(axis_in_card[i].tdata),
        .s_axis_tkeep(axis_in_card[i].tkeep),
        .s_axis_tlast(axis_in_card[i].tlast),
        .m_axis_tvalid(axis_fifo_src_tvalid[i]),
        .m_axis_tready(axis_fifo_src_tready[i]),
        .m_axis_tdata(axis_fifo_src_tdata[i]),
        .m_axis_tkeep(axis_fifo_src_tkeep[i]),
        .m_axis_tlast(axis_fifo_src_tlast[i])
    );
end

// Mux
always_comb begin
    // Sink
    axis_in_user_tready = &axis_fifo_sink_tready;

    for(int i = 0; i < N_DDR_CHAN; i++) begin
        axis_fifo_sink_tdata[i] = axis_in_user_tdata[i*AXI_DATA_BITS+:AXI_DATA_BITS];
        axis_fifo_sink_tkeep[i] = axis_in_user_tkeep[i*AXI_DATA_BITS/8+:AXI_DATA_BITS/8];
        axis_fifo_sink_tlast[i] = 1'b0;
        axis_fifo_sink_tvalid[i] = axis_in_user_tready & axis_in_user_tvalid;
    end

    // Src
    axis_out_user_tlast = axis_fifo_src_tlast[N_DDR_CHAN-1];
    axis_out_user_tvalid = &axis_fifo_src_tvalid;

    for(int i = 0; i < N_DDR_CHAN; i++) begin
        axis_out_user_tdata[i*AXI_DATA_BITS+:AXI_DATA_BITS] = axis_fifo_src_tdata[i];
        axis_out_user_tkeep[i*AXI_DATA_BITS/8+:AXI_DATA_BITS/8] = axis_fifo_src_tkeep[i];

        axis_fifo_src_tready[i] = axis_out_user_tvalid & axis_out_user_tready;
    end
end

endmodule
