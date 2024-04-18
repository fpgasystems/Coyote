/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

// Consts
localparam integer N_AES_PIPELINES = 4;
localparam integer KEY_ROUNDS = 11;

// CSR
logic [PID_BITS-1:0] mux_ctid; // go to card with this ctid
logic [128*KEY_ROUNDS-1:0] key_dec;
logic [128*KEY_ROUNDS-1:0] key_enc;
logic [128-1:0] key_slv;
logic key_start;

rdma_aes_slv inst_rdma_aes_slv (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key_out(key_slv),
    .keyStart(key_start),

    .mux_ctid(mux_ctid)
);

AXI4SR axis_s0_send ();
AXI4SR axis_s0_recv ();

mux_host_card_rd_rdma inst_mux_send (
    .aclk(aclk),
    .aresetn(aresetn),

    .mux_ctid(mux_ctid),
    .s_rq(rq_rd),
    .m_sq(sq_rd),

    .s_axis_host(axis_host_recv[0]),
    .s_axis_card(axis_card_recv[0]),
    .m_axis(axis_s0_send)
);  

mux_host_card_wr_rdma inst_mux_recv (
    .aclk(aclk),
    .aresetn(aresetn),

    .mux_ctid(mux_ctid),
    .s_rq(rq_wr),
    .m_sq(sq_wr),

    .s_axis(axis_s0_recv),
    .m_axis_host(axis_host_send[0]),
    .m_axis_card(axis_card_send[0])
);

//
// AES encryption and decryption
//

// Key decryption
key_top #(
    .OPERATION(1)  
) inst_key_top_dec (
    .clk(aclk),
    .reset_n(aresetn),
    
    .stall(1'b0),

    .key_in(key_slv),
    .keyVal_in(keyStart),
    .keyVal_out(),
    .key_out(key_dec)
);

// AES pipeline - receive (decrypt)
aes_top #(
    .NPAR(N_AES_PIPELINES),
    .OPERATION(1), // 0 - enc, 1 - dec
    .MODE(0) // 0 - ECB, 1 - CTR, 2 - CBC
) inst_aes_top_dec (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_s0_recv.tready),
    // Key
    .key_in(key_dec),
    //
    .last_in(axis_rdma_recv[0].tlast),
    .last_out(axis_s0_recv.tlast),
    .keep_in(axis_rdma_recv[0].tkeep),
    .keep_out(axis_s0_recv.tkeep),
    // Data
    .dVal_in(axis_rdma_recv[0].tvalid),
    .dVal_out(axis_s0_recv.tvalid),
    .data_in(axis_rdma_recv[0].tdata),
    .data_out(axis_s0_recv.tdata),
    // Counter mode
    .cntr_in(0)
);

assign axis_rdma_recv[0].tready = axis_s0_recv.tready;
assign axis_s0_recv.tid = 0;

// Key encryption
key_top #(
    .OPERATION(1)  
) inst_key_top_enc (
    .clk(aclk),
    .reset_n(aresetn),
    
    .stall(1'b0),

    .key_in(key_slv),
    .keyVal_in(keyStart),
    .keyVal_out(),
    .key_out(key_enc)
);

// AES pipeline - send (encrypt)
aes_top #(
    .NPAR(N_AES_PIPELINES),
    .OPERATION(0), // 0 - enc, 1 - dec
    .MODE(0) // 0 - ECB, 1 - CTR, 2 - CBC
) inst_aes_top_enc (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_rdma_send[0].tready),
    // Key
    .key_in(key),
    //
    .last_in(axis_s0_send.tlast),
    .last_out(axis_rdma_send[0].tlast),
    .keep_in(axis_s0_send.tkeep),
    .keep_out(axis_rdma_send[0].tkeep),
    // Data
    .dVal_in(axis_s0_send.tvalid),
    .dVal_out(axis_rdma_send[0].tvalid),
    .data_in(axis_s0_send.tdata),
    .data_out(axis_rdma_send[0].tdata),
    // Counter mode
    .cntr_in(0)
);

assign axis_s0_send.tready = axis_rdma_send[0].tready;
assign axis_rdma_send[0].tid = 0;

//
// Tie-off unused
//

always_comb notify.tie_off_m();
always_comb cq_wr.tie_off_s();
always_comb cq_rd.tie_off_s();