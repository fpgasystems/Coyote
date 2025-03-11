/////////////////////////////////////////////////////////
//                   HOST INPUTS                      //
///////////////////////////////////////////////////////
localparam integer AXI_AES_BITS = 128;

logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0]        axis_host_recv_tdata;
logic [N_STRM_AXI-1:0]                          axis_host_recv_tvalid;
logic [N_STRM_AXI-1:0]                          axis_host_recv_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0]      axis_host_recv_tkeep;
logic [N_STRM_AXI-1:0]                          axis_host_recv_tlast;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0]         axis_host_recv_tid;

// Data width converter: Coyote is built around 512-bit AXI streams but the encryption block expects 128-bit inputs
// NOTE: Coyote makes no assumptions (or guarantees) about the TID of a stream
// And here, the i-th stream should have TID = i, to match the i-th Coyote Thread in software
// Therefore, pass i here to the s_axis_tid port and it will be propagated all the way to the output through all the other blocks
for (genvar i = 0; i < N_STRM_AXI; i++) begin
    dwidth_input_512_128 inst_dwidth_input (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axis_tdata(axis_host_recv[i].tdata),
        .s_axis_tvalid(axis_host_recv[i].tvalid),
        .s_axis_tready(axis_host_recv[i].tready),
        .s_axis_tkeep(axis_host_recv[i].tkeep),
        .s_axis_tlast(axis_host_recv[i].tlast),
        .s_axis_tid(i),

        .m_axis_tdata(axis_host_recv_tdata[i]),
        .m_axis_tvalid(axis_host_recv_tvalid[i]),
        .m_axis_tready(axis_host_recv_tready[i]),
        .m_axis_tkeep(axis_host_recv_tkeep[i]),
        .m_axis_tlast(axis_host_recv_tlast[i]),
        .m_axis_tid(axis_host_recv_tid[i])
    );
end

/////////////////////////////////////////////////////////
//              AES INPUTS W/ FEEDBACK                //
///////////////////////////////////////////////////////
/*
AES CBC is a block sequential algorithm, so encryption is performed on text of fixed length (128b)
The encryption depends on the current chunk of text and the last encrypted chunk
That is output[t] = AES(input[t] XOR output[t-1]), for t = 0, output[0] = iv 
In our case, output[t-1] is called axis_fback_out
To avoid back-pressure, it's buffered in a FIFO, producing axis_fback_in, which is then used to calculate the next input
*/
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0]        axis_fback_in_tdata;
logic [N_STRM_AXI-1:0]                          axis_fback_in_tvalid;
logic [N_STRM_AXI-1:0]                          axis_fback_in_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0]      axis_fback_in_tkeep;
logic [N_STRM_AXI-1:0]                          axis_fback_in_tlast;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0]         axis_fback_in_tid;

logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0]        axis_fback_out_tdata;
logic [N_STRM_AXI-1:0]                          axis_fback_out_tvalid;
logic [N_STRM_AXI-1:0]                          axis_fback_out_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0]      axis_fback_out_tkeep;
logic [N_STRM_AXI-1:0]                          axis_fback_out_tlast;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0]         axis_fback_out_tid;

// Buffer feedback in FIFO, to avoid back-pressure
for (genvar i = 0; i < N_STRM_AXI; i++) begin
    axis_data_fifo_cbc inst_axis_data_fifo_cbc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),

        .s_axis_tdata(axis_fback_out_tdata[i]),
        .s_axis_tvalid(axis_fback_out_tvalid[i]),
        .s_axis_tready(axis_fback_out_tready[i]),
        .s_axis_tkeep(axis_fback_out_tkeep[i]),
        .s_axis_tlast(axis_fback_out_tlast[i]),
        .s_axis_tid(axis_fback_out_tid[i]),

        .m_axis_tdata(axis_fback_in_tdata[i]),
        .m_axis_tvalid(axis_fback_in_tvalid[i]),
        .m_axis_tready(axis_fback_in_tready[i]),
        .m_axis_tkeep(axis_fback_in_tkeep[i]),
        .m_axis_tlast(axis_fback_in_tlast[i]),
        .m_axis_tid(axis_fback_in_tid[i])
    );
end

// Compute new input for AES block, from current host input and the feedback value (IV or prev. encrypted text) 
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0]        axis_aes_in_tdata;
logic [N_STRM_AXI-1:0]                          axis_aes_in_tvalid;
logic [N_STRM_AXI-1:0]                          axis_aes_in_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0]      axis_aes_in_tkeep;
logic [N_STRM_AXI-1:0]                          axis_aes_in_tlast;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0]         axis_aes_in_tid;

for (genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_aes_in_tvalid[i]    = axis_host_recv_tvalid[i] & axis_fback_in_tvalid[i];
    assign axis_aes_in_tkeep[i]     = axis_host_recv_tkeep[i];
    assign axis_aes_in_tlast[i]     = axis_host_recv_tlast[i];
    assign axis_aes_in_tid[i]       = axis_host_recv_tid[i];
    
    // Calculate next input, by doing a XOR between last output and current input
    for(genvar j = 0; j < AXI_AES_BITS/8; j++) begin
        assign axis_aes_in_tdata[i][j * 8 +: 8] = (axis_host_recv_tkeep[i][j]) ? 
                                                    (axis_host_recv_tdata[i][j * 8 +: 8] ^ axis_fback_in_tdata[i][j * 8 +: 8]) : 8'b0;
    end
    
    assign axis_fback_in_tready[i]  = axis_aes_in_tready[i] & axis_aes_in_tvalid[i];
    assign axis_host_recv_tready[i] = axis_aes_in_tready[i] & axis_aes_in_tvalid[i];
end

/////////////////////////////////////////////////////////
//              ROUND ROBIN ARBITRATION               //
///////////////////////////////////////////////////////
logic [AXI_AES_BITS-1:0]        axis_aes_active_in_tdata;
logic                           axis_aes_active_in_tvalid;
logic                           axis_aes_active_in_tready;
logic [AXI_AES_BITS/8-1:0]      axis_aes_active_in_tkeep;
logic                           axis_aes_active_in_tlast;
logic [AXI_ID_BITS-1:0]         axis_aes_active_in_tid;

// Coyote provides a Round Robin IP that can be instantiated in the vFPGA
axisr_arbiter #(
    .N_ID(N_STRM_AXI),
    .DATA_BITS(AXI_AES_BITS),
    .ID_BITS(AXI_ID_BITS)
) inst_arbiter (
    .aclk(aclk),
    .aresetn(aresetn),

    .tdata_snk(axis_aes_in_tdata),
    .tvalid_snk(axis_aes_in_tvalid),
    .tready_snk(axis_aes_in_tready),
    .tkeep_snk(axis_aes_in_tkeep),
    .tlast_snk(axis_aes_in_tlast),
    .tid_snk(axis_aes_in_tid),

    .tdata_src(axis_aes_active_in_tdata),
    .tvalid_src(axis_aes_active_in_tvalid),
    .tready_src(axis_aes_active_in_tready),
    .tkeep_src(axis_aes_active_in_tkeep),
    .tlast_src(axis_aes_active_in_tlast),
    .tid_src(axis_aes_active_in_tid)
);

/////////////////////////////////////////////////////////
//               CONTROL REGISTERS                    //
///////////////////////////////////////////////////////
// Parses the encryption key and IV, set by the user from the software, using setCSR(...)
// For more details, see hdl/aes_axi_ctrl_parser.sv and the user software
logic key_valid;
logic [127:0] key;

logic iv_valid;
logic [127:0] iv;
logic [AXI_ID_BITS-1:0] iv_dest;

aes_axi_ctrl_parser inst_aes_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),

    .axi_ctrl(axi_ctrl),

    .key(key),
    .key_valid(key_valid),

    .iv(iv),
    .iv_dest(iv_dest),
    .iv_valid(iv_valid)
);

logic [N_STRM_AXI-1:0] iv_start;
always_comb begin
    for(int i = 0; i < N_STRM_AXI; i++) begin
        iv_start[i] = (iv_dest == i) ? iv_valid : 1'b0;
    end
end

/////////////////////////////////////////////////////////
//               ENCRYPTION MODULE                    //
///////////////////////////////////////////////////////
// Output from encrytion module
logic [AXI_AES_BITS-1:0]    axis_aes_active_out_tdata;
logic                       axis_aes_active_out_tvalid;
logic                       axis_aes_active_out_tready;
logic [AXI_AES_BITS/8-1:0]  axis_aes_active_out_tkeep;
logic                       axis_aes_active_out_tlast;
logic [AXI_ID_BITS-1:0]     axis_aes_active_out_tid;

// AES module
aes_top #(
    .NPAR(1)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_aes_active_out_tready),

    .key_in(key),
    .keyVal_in(key_valid),
    .keyVal_out(),

    .data_in(axis_aes_active_in_tdata),
    .dVal_in(axis_aes_active_in_tvalid),
    .keep_in(axis_aes_active_in_tkeep),
    .last_in(axis_aes_active_in_tlast),
    .id_in(axis_aes_active_in_tid),

    .data_out(axis_aes_active_out_tdata),
    .dVal_out(axis_aes_active_out_tvalid),
    .keep_out(axis_aes_active_out_tkeep),
    .last_out(axis_aes_active_out_tlast),
    .id_out(axis_aes_active_out_tid)
);

assign axis_aes_active_in_tready = axis_aes_active_out_tready;
assign axis_aes_active_out_tready = axis_host_send_tready[axis_aes_active_out_tid] & (axis_aes_active_out_tlast ? 1'b1 : axis_fback_out_tready[axis_aes_active_out_tid]);

// Calculate the feedback:
//  - On the first time-step, it's equal to the IV
//  - On all others, it's equal to the previous output 
for (genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_fback_out_tvalid[i] =  iv_start[i] ? 1'b1 :
                                            (((i == axis_aes_active_out_tid) && ~axis_aes_active_out_tlast) ? axis_aes_active_out_tvalid & axis_aes_active_out_tready : 1'b0);

    assign axis_fback_out_tdata[i]  = iv_start[i] ? iv : axis_aes_active_out_tdata;
    assign axis_fback_out_tkeep[i]  = iv_start[i] ? ~0 : axis_aes_active_out_tkeep;
    assign axis_fback_out_tlast[i]  = iv_start[i] ? 1'b0 : axis_aes_active_out_tlast;
    assign axis_fback_out_tid[i]    = iv_start[i] ? i : axis_aes_active_out_tid;
end

/////////////////////////////////////////////////////////
//                    OUTPUTS                         //
///////////////////////////////////////////////////////
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0]       axis_host_send_tdata;
logic [N_STRM_AXI-1:0]                         axis_host_send_tvalid;
logic [N_STRM_AXI-1:0]                         axis_host_send_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0]     axis_host_send_tkeep;
logic [N_STRM_AXI-1:0]                         axis_host_send_tlast;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0]        axis_host_send_tid;

for (genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_host_send_tdata[i]  = axis_aes_active_out_tdata;
    assign axis_host_send_tvalid[i] = (i == axis_aes_active_out_tid) ? axis_aes_active_out_tvalid & axis_aes_active_out_tready : 0;
    assign axis_host_send_tkeep[i]  = axis_aes_active_out_tkeep;
    assign axis_host_send_tlast[i]  = axis_aes_active_out_tlast;
    assign axis_host_send_tid[i]    = axis_aes_active_out_tid;
end

// Data width converter: Coyote is built around 512-bit AXI streams but the encryption block produces 128-bit outputs
for (genvar i = 0; i < N_STRM_AXI; i++) begin
    dwidth_output_128_512 inst_dwidth_output (
        .aclk(aclk),
        .aresetn(aresetn),

        .s_axis_tdata (axis_host_send_tdata[i]),
        .s_axis_tvalid(axis_host_send_tvalid[i]),
        .s_axis_tready(axis_host_send_tready[i]),
        .s_axis_tkeep (axis_host_send_tkeep[i]),
        .s_axis_tlast (axis_host_send_tlast[i]),
        .s_axis_tid   (axis_host_send_tid[i]),

        .m_axis_tdata (axis_host_send[i].tdata),
        .m_axis_tvalid(axis_host_send[i].tvalid),
        .m_axis_tready(axis_host_send[i].tready),
        .m_axis_tkeep (axis_host_send[i].tkeep),
        .m_axis_tlast (axis_host_send[i].tlast),
        .m_axis_tid   (axis_host_send[i].tid)
    );
end

/////////////////////////////////////////////////////////
//                       MISC                         //
///////////////////////////////////////////////////////
// Tie-off unused signals to avoid synthesis problems
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

// Debug ILA
ila_aes_mt inst_ila_aes_mt (
    .clk(aclk),

    .probe0(axis_aes_active_in_tdata),          // 128
    .probe1(axis_aes_active_in_tvalid),         // 1
    .probe2(axis_aes_active_in_tready),         // 1
    .probe3(axis_aes_active_in_tkeep),          // 16
    .probe4(axis_aes_active_in_tlast),          // 1
    .probe5(axis_aes_active_in_tid),            // 6

    .probe6(axis_aes_active_out_tdata),         // 128
    .probe7(axis_aes_active_out_tvalid),        // 1
    .probe8(axis_aes_active_out_tready),        // 1
    .probe9(axis_aes_active_out_tkeep),         // 16
    .probe10(axis_aes_active_out_tlast),        // 1
    .probe11(axis_aes_active_out_tid),          // 6

    .probe12(key),                              // 128
    .probe13(key_valid),                        // 1

    .probe14(iv),                               // 128
    .probe15(iv_dest),                          // 6
    .probe16(iv_valid)                          // 1
);
