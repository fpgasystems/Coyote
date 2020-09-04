import lynxTypes::*;

/**
 * Multi channel data multiplexer - host signals
 */
module axis_mux_ddr_host (
    input  logic                            aclk,
    input  logic                            aresetn,

    AXI4S.s                                 axis_in_host,
    AXI4S.m                                 axis_out_host,

    AXI4S.m                                 axis_out_card [N_DDR_CHAN],
    AXI4S.s                                 axis_in_card [N_DDR_CHAN]
);

// Params
localparam integer N_DDR_CHAN_BITS = $clog2(N_DDR_CHAN);

// Internal regs
logic [N_DDR_CHAN_BITS-1:0] sel_sink_r;
logic [N_DDR_CHAN_BITS-1:0] sel_src_r;

// ----------------------------------------------------------------------------------------------------------------------- 
// interface loop issues => temp signals
// ----------------------------------------------------------------------------------------------------------------------- 
logic                                             axis_in_host_tvalid;
logic                                             axis_in_host_tready;
logic [AXI_DATA_BITS-1:0]                         axis_in_host_tdata;
logic [AXI_DATA_BITS/8-1:0]                       axis_in_host_tkeep;
logic                                             axis_in_host_tlast;

logic                                             axis_out_host_tvalid;
logic                                             axis_out_host_tready;
logic [AXI_DATA_BITS-1:0]                         axis_out_host_tdata;
logic [AXI_DATA_BITS/8-1:0]                       axis_out_host_tkeep;
logic                                             axis_out_host_tlast;

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

// Assign
assign axis_in_host_tvalid = axis_in_host.tvalid;
assign axis_in_host_tdata = axis_in_host.tdata;
assign axis_in_host_tkeep = axis_in_host.tkeep;
assign axis_in_host_tlast = axis_in_host.tlast;
assign axis_in_host.tready = axis_in_host_tready;

assign axis_out_host.tvalid = axis_out_host_tvalid;
assign axis_out_host.tdata = axis_out_host_tdata;
assign axis_out_host.tkeep = axis_out_host_tkeep;
assign axis_out_host.tlast = axis_out_host_tlast;
assign axis_out_host_tready = axis_out_host.tready;

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
    for(int i = 0; i < N_DDR_CHAN; i++) begin
        axis_fifo_sink_tdata[i] = axis_in_host_tdata;
        axis_fifo_sink_tkeep[i] = axis_in_host_tkeep;
        axis_fifo_sink_tlast[i] = 1'b0;
        axis_fifo_sink_tvalid[i] = (sel_sink_r == i) ? axis_in_host_tvalid : 1'b0; 
    end
    axis_in_host_tready = axis_fifo_sink_tready[sel_sink_r];

    // Src
    for(int i = 0; i < N_DDR_CHAN; i++) begin
        axis_fifo_src_tready[i] = (sel_src_r == i) ? axis_out_host_tready : 1'b0;
    end
    axis_out_host_tdata = axis_fifo_src_tdata[sel_src_r];
    axis_out_host_tkeep = axis_fifo_src_tkeep[sel_src_r];
    axis_out_host_tlast = 1'b0;
    axis_out_host_tvalid = axis_fifo_src_tvalid[sel_src_r];
end

always_ff @(posedge aclk, negedge aresetn) begin
  if (~aresetn) begin 
    sel_sink_r <= 0;
    sel_src_r <= 0;
  end
  else begin
    sel_sink_r <= (axis_in_host_tvalid & axis_in_host_tready) ? sel_sink_r + 1 : sel_sink_r;
    sel_src_r <= (axis_out_host_tvalid & axis_out_host_tready) ? sel_src_r + 1 : sel_src_r;
   end
end

endmodule