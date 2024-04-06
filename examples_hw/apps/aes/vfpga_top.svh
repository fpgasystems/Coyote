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
logic [128*KEY_ROUNDS-1:0] key_dec;
logic [128*KEY_ROUNDS-1:0] key_enc;
logic [128-1:0] key_slv;
logic key_start;

aes_slv inst_rdma_aes_slv (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key_out(key_slv),
    .keyStart(key_start)
);

//
// AES encryption
//

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
    .MODE(2) // 0 - ECB, 1 - CTR, 2 - CBC
) inst_aes_top_enc (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_host_send[0].tready),
    // Key
    .key_in(key),
    //
    .last_in(axis_host_recv.tlast),
    .last_out(axis_host_send[0].tlast),
    .keep_in(axis_host_recv.tkeep),
    .keep_out(axis_host_send[0].tkeep),
    // Data
    .dVal_in(axis_host_recv.tvalid),
    .dVal_out(axis_host_send[0].tvalid),
    .data_in(axis_host_recv.tdata),
    .data_out(axis_host_send[0].tdata),
    // Counter mode
    .cntr_in(0)
);

assign axis_host_recv.tready = axis_host_send[0].tready;
assign axis_host_send[0].tid = 0;

//
// Tie-off unused
//

always_comb notify.tie_off_m();
always_comb cq_wr.tie_off_s();
always_comb cq_rd.tie_off_s();