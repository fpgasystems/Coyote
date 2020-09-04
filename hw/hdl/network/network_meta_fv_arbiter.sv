import lynxTypes::*;

/**
 *	Network meta RPC arbiter
 */ 
module network_meta_fv_arbiter #( 
    parameter integer DATA_BITS         = 32
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                           meta_snk,
    metaIntf.m                           meta_src [N_REGIONS]
);

logic ready_snk;
logic valid_snk;
logic [DATA_BITS-1:0] data_snk;
logic [N_REGIONS-1:0] ready_src;
logic [N_REGIONS-1:0] valid_src;
logic [N_REGIONS-1:0][DATA_BITS-1:0] data_src;

logic [N_REQUEST_BITS-1:0] id;

metaIntf #(.DATA_BITS(FV_REQ_BITS)) meta_que [N_REGIONS] ();

// --------------------------------------------------------------------------------
// -- I/O !!! interface
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign meta_que[i].valid = valid_src[i];
    assign ready_src[i] = meta_que[i].ready;
    assign meta_que[i].data = data_src[i];   
end

assign valid_snk = meta_snk.valid;
assign meta_snk.ready = ready_snk;
assign data_snk = meta_snk.data;

// --------------------------------------------------------------------------------
// -- Mux 
// --------------------------------------------------------------------------------
always_comb begin
    id = data_snk[29+:4]; // Switch to interface, this is messy

    for(int i = 0; i < N_REGIONS; i++) begin
        valid_src[i] = (id == i) ? valid_snk : 1'b0;
        data_src[i] = data_snk;
    end
    ready_snk = ready_src[id];
end

for(genvar i = 0; i < N_REGIONS; i++) begin
    axis_data_fifo_cnfg_rdma_256 inst_fv_queue_in (
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(meta_que[i].valid),
    .s_axis_tready(meta_que[i].ready),
    .s_axis_tdata(meta_que[i].data),
    .m_axis_tvalid(meta_src[i].valid),
    .m_axis_tready(meta_src[i].ready),
    .m_axis_tdata(meta_src[i].data),
    .axis_wr_data_count()
    );
end

endmodule