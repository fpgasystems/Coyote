/**
 * VFPGA TOP
 *
 * Tie up all signals to the user kernels
 * Still to this day, interfaces are not supported by Vivado packager ...
 * This means verilog style port connections are needed.
 * 
 */

localparam integer AXI_AES_BITS = 128;

// 
logic [N_STRM_AXI-1:0] axis_host_recv_tvalid;
logic [N_STRM_AXI-1:0] axis_host_recv_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_host_recv_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_host_recv_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_host_recv_tid;
logic [N_STRM_AXI-1:0] axis_host_recv_tlast;

logic [N_STRM_AXI-1:0] axis_host_send_tvalid;
logic [N_STRM_AXI-1:0] axis_host_send_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_host_send_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_host_send_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_host_send_tid;
logic [N_STRM_AXI-1:0] axis_host_send_tlast;

logic [N_STRM_AXI-1:0] axis_s0_tvalid;
logic [N_STRM_AXI-1:0] axis_s0_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_s0_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_s0_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_s0_tid;
logic [N_STRM_AXI-1:0] axis_s0_tlast;

logic axis_s1_tvalid;
logic axis_s1_tready;
logic [AXI_AES_BITS-1:0] axis_s1_tdata;
logic [AXI_AES_BITS/8-1:0] axis_s1_tkeep;
logic [AXI_ID_BITS-1:0] axis_s1_tid;
logic axis_s1_tlast;

logic axis_s2_tvalid;
logic axis_s2_tready;
logic [AXI_AES_BITS-1:0] axis_s2_tdata;
logic [AXI_AES_BITS/8-1:0] axis_s2_tkeep;
logic [AXI_ID_BITS-1:0] axis_s2_tid;
logic axis_s2_tlast;

logic [N_STRM_AXI-1:0] axis_fback_in_tvalid;
logic [N_STRM_AXI-1:0] axis_fback_in_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_fback_in_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_fback_in_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_fback_in_tid;
logic [N_STRM_AXI-1:0] axis_fback_in_tlast;

logic [N_STRM_AXI-1:0] axis_fback_in_2_tvalid;
logic [N_STRM_AXI-1:0] axis_fback_in_2_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_fback_in_2_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_fback_in_2_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_fback_in_2_tid;
logic [N_STRM_AXI-1:0] axis_fback_in_2_tlast;

logic [N_STRM_AXI-1:0] axis_fback_out_tvalid;
logic [N_STRM_AXI-1:0] axis_fback_out_tready;
logic [N_STRM_AXI-1:0][AXI_AES_BITS-1:0] axis_fback_out_tdata;
logic [N_STRM_AXI-1:0][AXI_AES_BITS/8-1:0] axis_fback_out_tkeep;
logic [N_STRM_AXI-1:0][AXI_ID_BITS-1:0] axis_fback_out_tid;
logic [N_STRM_AXI-1:0] axis_fback_out_tlast;

// I/O
for(genvar i = 0; i < N_STRM_AXI; i++) begin
    dwidth_sink_512_128 inst_dwidth_sink (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_host_recv[i].tvalid),
        .s_axis_tready(axis_host_recv[i].tready),
        .s_axis_tdata (axis_host_recv[i].tdata),
        .s_axis_tkeep (axis_host_recv[i].tkeep),
        .s_axis_tlast (axis_host_recv[i].tlast),
        .s_axis_tid   (axis_host_recv[i].tid),
        .m_axis_tvalid(axis_host_recv_tvalid[i]),
        .m_axis_tready(axis_host_recv_tready[i]),
        .m_axis_tdata (axis_host_recv_tdata[i]),
        .m_axis_tkeep (axis_host_recv_tkeep[i]),
        .m_axis_tlast (axis_host_recv_tlast[i]),
        .m_axis_tid   (axis_host_recv_tid[i])
    );

    dwidth_src_128_512 inst_dwidth_src (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_host_send_tvalid[i]),
        .s_axis_tready(axis_host_send_tready[i]),
        .s_axis_tdata (axis_host_send_tdata[i]),
        .s_axis_tkeep (axis_host_send_tkeep[i]),
        .s_axis_tlast (axis_host_send_tlast[i]),
        .s_axis_tid   (axis_host_send_tid[i]),
        .m_axis_tvalid(axis_host_send[i].tvalid),
        .m_axis_tready(axis_host_send[i].tready),
        .m_axis_tdata (axis_host_send[i].tdata),
        .m_axis_tkeep (axis_host_send[i].tkeep),
        .m_axis_tlast (axis_host_send[i].tlast),
        .m_axis_tid   (axis_host_send[i].tid)
    );
end

// Mux input
for(genvar i = 0; i < N_STRM_AXI; i++) begin
    axis_data_fifo_cbc inst_axis_data_fifo_cbc (
        .s_axis_aclk(aclk),
        .s_axis_aresetn(aresetn),

        .s_axis_tvalid(axis_fback_in_2_tvalid[i]),
        .s_axis_tready(axis_fback_in_2_tready[i]),
        .s_axis_tdata(axis_fback_in_2_tdata[i]),
        .s_axis_tkeep(axis_fback_in_2_tkeep[i]),
        .s_axis_tlast(axis_fback_in_2_tlast[i]),
        .s_axis_tid(axis_fback_in_2_tid[i]),

        .m_axis_tvalid(axis_fback_out_tvalid[i]),
        .m_axis_tready(axis_fback_out_tready[i]),
        .m_axis_tdata(axis_fback_out_tdata[i]),
        .m_axis_tkeep(axis_fback_out_tkeep[i]),
        .m_axis_tlast(axis_fback_out_tlast[i]),
        .m_axis_tid(axis_fback_out_tid[i])
    );
end

for(genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_s0_tvalid[i] = axis_host_recv_tvalid[i] & axis_fback_out_tvalid[i];
    assign axis_host_recv_tready[i] = axis_s0_tvalid[i] & axis_s0_tready[i];
    assign axis_fback_out_tready[i] = axis_s0_tvalid[i] & axis_s0_tready[i];
    
    assign axis_s0_tdata[i] = axis_host_recv_tdata[i] | axis_fback_out_tdata[i];
    assign axis_s0_tlast[i] = axis_host_recv_tlast[i];
    assign axis_s0_tkeep[i] = axis_host_recv_tkeep[i];
    assign axis_s0_tid[i]   = i;
end

// RR 
axisr_arbiter #(
    .N_ID(N_STRM_AXI)
) inst_sink_arbiter (
    .aclk(aclk),
    .aresetn(aresetn),

    .tready_snk(axis_s0_tready),
    .tvalid_snk(axis_s0_tvalid),
    .tdata_snk(axis_s0_tdata),
    .tkeep_snk(axis_s0_tkeep),
    .tlast_snk(axis_s0_tlast),
    .tid_snk(axis_s0_tid),

    .tready_src(axis_s1_tready),
    .tvalid_src(axis_s1_tvalid),
    .tdata_src(axis_s1_tdata),
    .tkeep_src(axis_s1_tkeep),
    .tlast_src(axis_s1_tlast),
    .tid_src(axis_s1_tid)
);
assign axis_s1_tready = axis_s2_tready;

//
// AES top
//
localparam integer N_AES_PIPELINES = 1;
localparam integer N_STRM_AXI_BITS = clog2s(N_STRM_AXI);

logic [127:0] key;
logic key_start;
logic [127:0] iv;
logic [N_STRM_AXI_BITS-1:0] iv_dest;
logic iv_start;

logic [N_STRM_AXI-1:0][127:0] iv_fback;
logic [N_STRM_AXI-1:0] iv_start_fback;


// Slave
aes_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .key_out(key),
    .keyStart(key_start),
    .iv_out(iv),
    .ivDest(iv_dest),
    .ivStart(iv_start)
);

// Mux IV
always_comb begin
    for(int i = 0; i < N_STRM_AXI; i++) begin
        iv_start_fback[i] = (iv_dest == i) ? iv_start : 1'b0;
        iv_fback[i] = iv;
    end
end

// AES pipelines
aes_top #(
    .NPAR(N_AES_PIPELINES)
) inst_aes_top (
    .clk(aclk),
    .reset_n(aresetn),
    .stall(~axis_s2_tready),
    .key_in(key),
    .keyVal_in(key_start),
    .keyVal_out(),
    .last_in(axis_s1_tlast),
    .last_out(axis_s2_tlast),
    .keep_in(axis_s1_tkeep),
    .keep_out(axis_s2_tkeep),
    .id_in(axis_s1_tid),
    .id_out(axis_s2_tid),
    .dVal_in(axis_s1_tvalid),
    .dVal_out(axis_s2_tvalid),
    .data_in(axis_s1_tdata),
    .data_out(axis_s2_tdata)
);

// Mux output
assign axis_s2_tready = axis_host_send_tready[axis_s2_tid] & (axis_s2_tlast ? 1'b1 : axis_fback_in_tready[axis_s2_tid]);

for(genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_host_send_tvalid[i] = (i == axis_s2_tid) ? axis_s2_tvalid & axis_s2_tready : 1'b0;
    assign axis_fback_in_tvalid[i] =  ((i == axis_s2_tid) && ~axis_s2_tlast) ? axis_s2_tvalid & axis_s2_tready : 1'b0;

    assign axis_host_send_tdata[i] = axis_s2_tdata;
    assign axis_host_send_tkeep[i] = axis_s2_tkeep;
    assign axis_host_send_tlast[i] = axis_s2_tlast;
    assign axis_host_send_tid[i]   = axis_s2_tid;

    assign axis_fback_in_tdata[i] = axis_s2_tdata;
    assign axis_fback_in_tkeep[i] = axis_s2_tkeep;
    assign axis_fback_in_tlast[i] = axis_s2_tlast;
    assign axis_fback_in_tid[i]   = axis_s2_tid;
end

for(genvar i = 0; i < N_STRM_AXI; i++) begin
    assign axis_fback_in_tready[i]   = axis_fback_in_2_tready[i];
    assign axis_fback_in_2_tvalid[i] = iv_start_fback[i] ? 1'b1          : axis_fback_in_tvalid[i];
    assign axis_fback_in_2_tdata[i]  = iv_start_fback[i] ? iv_fback[i]   : axis_fback_in_tdata[i];
    assign axis_fback_in_2_tkeep[i]  = iv_start_fback[i] ? ~0            : axis_fback_in_tkeep[i];
    assign axis_fback_in_2_tlast[i]  = iv_start_fback[i] ? 1'b0          : axis_fback_in_tlast[i];
    assign axis_fback_in_2_tid[i]    = iv_start_fback[i] ? i             : axis_fback_in_tid[i];
end

// Tie-off the rest of the interfaces
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

//
// DBG
//

ila_0 inst_ila_0 (
    .clk(aclk),
    
    .probe0(axis_host_recv_tvalid), // 8
    .probe1(axis_host_recv_tready), // 8
    .probe2(axis_host_recv_tlast), // 8
    .probe3(axis_host_send_tvalid), // 8
    .probe4(axis_host_send_tready), // 8
    .probe5(axis_host_send_tlast), // 8
    .probe6(iv_start_fback), // 8
    .probe7(iv_start),
    .probe8(axis_s0_tvalid), // 8
    .probe9(axis_s0_tready), // 8
    .probe10(axis_s0_tlast), // 8
    .probe11(axis_s1_tvalid),
    .probe12(axis_s1_tready),
    .probe13(axis_s1_tlast),
    .probe14(axis_s2_tvalid),
    .probe15(axis_s2_tready),
    .probe16(axis_s2_tlast),
    .probe17(axis_fback_in_tvalid), // 8
    .probe18(axis_fback_in_tready), // 8
    .probe19(axis_fback_in_tlast), // 8
    .probe20(axis_fback_in_2_tvalid), // 8
    .probe21(axis_fback_in_2_tready), // 8
    .probe22(axis_fback_in_2_tlast), // 8
    .probe23(axis_fback_out_tvalid), // 8
    .probe24(axis_fback_out_tready), // 8
    .probe25(axis_fback_out_tlast) // 8
);

