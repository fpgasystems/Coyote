always_comb notify.tie_off_m();

// I/O
AXI4SR axis_sink_int[N_CARD_AXI]();
AXI4SR axis_src_int[N_CARD_AXI]();

for (genvar i = 0; i < N_CARD_AXI; i++) begin
    axisr_reg inst_reg_sink_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_recv[i]), .m_axis(axis_sink_int[i]));
    axisr_reg inst_reg_src_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int[i]), .m_axis(axis_card_send[i]));
end

// packet sniffer slave 
// CSRs
logic [0:0]             sniffer_ctrl_0;      // control 0 (see below for details)
logic [0:0]             sniffer_ctrl_1;      // control 1 (see below for details)
logic [63:0]            sniffer_ctrl_filter; // sniffer filter config
logic [1:0]             sniffer_state;       // state (see below for details)
logic [31:0]            sniffer_size;        // size of captured packets
logic [63:0]            sniffer_timer;       // internal timer
logic [PID_BITS-1:0]    sniffer_host_pid;    // host pid
logic [DEST_BITS-1:0]   sniffer_host_dest;   // host dest
logic [VADDR_BITS-1:0]  sniffer_host_vaddr;  // host memory vaddr
logic [LEN_BITS-1:0]    sniffer_host_len;    // host memory length
// internal regs
logic [31:0]            wrote_len;           // size of wrote data length (should be equal to sniffer_size, otherwise insufficient memory bandwidth)
logic [31:0]            wrote_len_n;
logic                   req_sent_flg;
logic [3:0]             outstanding_req;     // number of outstanding sq_wr requests
logic                   within_packet_not_first;
logic                   within_packet;
logic                   within_packet_not_last;
// fixed parameters
parameter SIZE_PER_REQ_BIT = 15; 
parameter SIZE_PER_REQ     = 1 << SIZE_PER_REQ_BIT; // size per sq_wr request


AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) axis_sniffer_merged ();
packet_sniffer_sched inst_packet_sniffer_sched (
    .aclk(aclk),
    .aresetn(aresetn),
    .sink_rx(axis_rx_sniffer),
    .sink_tx(axis_tx_sniffer),
    .src(axis_sniffer_merged)
);

always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        within_packet_not_first <= 0;
    end else begin
        if (axis_sniffer_merged.tvalid && axis_sniffer_merged.tready) begin
            within_packet_not_first <= 1;
            if (axis_sniffer_merged.tlast) begin
                within_packet_not_first <= 0;
            end
        end
    end
end
assign within_packet          = within_packet_not_first | (axis_sniffer_merged.tvalid & axis_sniffer_merged.tready);
assign within_packet_not_last = within_packet & (~(axis_sniffer_merged.tvalid & axis_sniffer_merged.tready & axis_sniffer_merged.tlast));

always_comb begin
    axis_sniffer_merged.tready = 1'b1; // this should always be 1!!!
    filter_config.valid = 1'b1;
    filter_config.data  = sniffer_ctrl_filter;
    // e.g. 64'b00000000_00000000_00000000_00000000_00000000_10000000_00000000_00000000 (ignore udp/ipv4 payload)
end

/*
 *
 * sniffer_ctrl_0: 1 to start sniffering, 0 to end sniffering
 * sniffer_ctrl_1: 1 for host memory information ready (offloaded to card), 0 for host memory information invalid
 *
 * sniffer_state == 2'b00: idle       [if sniffer_ctrl_0 == 1 && sniffer_ctrl_1 == 1 goto state 2'b01]
 *               == 2'b01: sniffing   [if sniffer_ctrl_0 == 0                        goto state 2'b11]
 *               == 2'b11: finishing  [if all memory requests finished               goto state 2'b00]
 *               
 */

//
// CSRs
//
packet_sniffer_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .sniffer_ctrl_0(sniffer_ctrl_0),
    .sniffer_ctrl_1(sniffer_ctrl_1),
    .sniffer_ctrl_filter(sniffer_ctrl_filter),
    .sniffer_state(sniffer_state),
    .sniffer_size(sniffer_size),
    .sniffer_timer(sniffer_timer),
    .sniffer_host_pid(sniffer_host_pid),
    .sniffer_host_dest(sniffer_host_dest),
    .sniffer_host_vaddr(sniffer_host_vaddr),
    .sniffer_host_len(sniffer_host_len)
);

AXI4SR axis_sink_active ();
AXI4SR axis_src_active ();

// sink (card mem -> vfpga) 
// not used
assign axis_sink_active.tvalid = axis_sink_int[0].tvalid;
assign axis_sink_active.tkeep  = axis_sink_int[0].tkeep;
assign axis_sink_active.tlast  = axis_sink_int[0].tlast;
assign axis_sink_active.tdata  = axis_sink_int[0].tdata;
assign axis_sink_active.tid    = axis_sink_int[0].tid;
assign axis_sink_int[0].tready = axis_sink_active.tready;
// src  (vfpga -> card mem)
assign axis_src_int[0].tvalid = axis_src_active.tvalid;
assign axis_src_int[0].tkeep  = axis_src_active.tkeep;
assign axis_src_int[0].tlast  = axis_src_active.tlast;
assign axis_src_int[0].tdata  = axis_src_active.tdata;
assign axis_src_int[0].tid    = axis_src_active.tid;
assign axis_src_active.tready = axis_src_int[0].tready;

// Regs
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        wrote_len       <= 0;
        req_sent_flg    <= 0;
        outstanding_req <= 0;
    end else begin
        if (sniffer_state == 2'b00) begin
            wrote_len       <= 0;
            req_sent_flg    <= 0;
            outstanding_req <= 0;
        end else begin
            if (axis_src_active.tvalid && axis_src_active.tready) begin
                req_sent_flg    <= 0;
                wrote_len       <= wrote_len + 64;
            end
            if (sq_wr.valid && sq_wr.ready && cq_wr.valid && cq_wr.ready) begin
                req_sent_flg    <= 1;
                outstanding_req <= outstanding_req;
            end else if (sq_wr.valid && sq_wr.ready) begin
                req_sent_flg    <= 1;
                outstanding_req <= outstanding_req + 1;
            end else if (cq_wr.valid && cq_wr.ready) begin
                outstanding_req <= outstanding_req - 1;
            end
        end
    end
end

// States
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        sniffer_state   <= 2'b00;
        sniffer_size    <= 0;
        sniffer_timer   <= 0;
    end else begin
        case (sniffer_state)
            2'b00: begin
                if (sniffer_ctrl_0 && sniffer_ctrl_1 && (~within_packet_not_last)) begin
                    sniffer_state   <= 2'b01;
                    sniffer_size    <= 0;
                    sniffer_timer   <= 0;
                end
            end
            2'b01: begin
                sniffer_timer <= sniffer_timer + 1;
                if (axis_src_active.tvalid) begin
                    sniffer_size  <= sniffer_size + 64;
                end
                if ((~sniffer_ctrl_0) && (~within_packet_not_last)) begin
                    sniffer_state <= 2'b11;
                end
            end
            2'b11: begin
                if (wrote_len[SIZE_PER_REQ_BIT-1:0] == 0) begin
                // if (outstanding_req == 0 && wrote_len[SIZE_PER_REQ_BIT-1:0] == 0) begin
                    sniffer_state <= 2'b00;
                end
            end
            default: ;
        endcase
    end
end

// DP
always_comb begin
    wrote_len_n = wrote_len + 64;

    // Requests
    // Read from card (deactivated)
    sq_rd.data = 0;
    sq_rd.data.opcode = LOCAL_READ;
    sq_rd.data.strm = STRM_CARD;
    sq_rd.data.mode = 0;
    sq_rd.data.rdma = 0;
    sq_rd.data.remote = 0;
    sq_rd.data.pid = sniffer_host_pid;
    sq_rd.data.dest = sniffer_host_dest;
    sq_rd.data.last = 1'b1;
    sq_rd.data.vaddr = sniffer_host_vaddr;
    sq_rd.data.len = 0;
    sq_rd.valid = 1'b0;
    // Write to card
    sq_wr.data = 0;
    sq_wr.data.opcode = LOCAL_WRITE;
    sq_wr.data.strm = STRM_CARD;
    sq_wr.data.mode = 0;
    sq_wr.data.rdma = 0;
    sq_wr.data.remote = 0;
    sq_wr.data.pid = sniffer_host_pid;
    sq_wr.data.dest = sniffer_host_dest;
    sq_wr.data.last = 1'b1;
    sq_wr.data.vaddr = sniffer_host_vaddr + wrote_len;
    sq_wr.data.len = SIZE_PER_REQ;
    sq_wr.valid = ((sniffer_state == 2'b01) && req_sent_flg == 0 && wrote_len[SIZE_PER_REQ_BIT-1:0] == 0) ? 1'b1 : 1'b0;

    cq_rd.ready = 1'b1;
    cq_wr.ready = 1'b1;

    // Data
    axis_sink_active.tready = 1'b1;

    axis_src_active.tdata = axis_sniffer_merged.tdata;
    axis_src_active.tkeep = ~0;
    axis_src_active.tid   = 0;
    axis_src_active.tlast = ((sniffer_state == 2'b01 || sniffer_state == 2'b11) && wrote_len_n[SIZE_PER_REQ_BIT-1:0] == 0) ? 1'b1 : 1'b0;
    axis_src_active.tvalid = (sniffer_state == 2'b01 && wrote_len < sniffer_host_len) ? (axis_sniffer_merged.tvalid) : (
                             (sniffer_state == 2'b11 && wrote_len < sniffer_host_len) ? (wrote_len[SIZE_PER_REQ_BIT-1:0] != 0) : 1'b0);
end

// Debug

ila_packet_sniffer_vfpga inst_ila_packet_sniffer_vfpga (
    .clk(aclk),
    .probe0(sniffer_ctrl_0), // 1
    .probe1(sniffer_ctrl_1), // 1
    .probe2(sniffer_ctrl_filter), // 64
    .probe3(sniffer_state), // 2
    .probe4(sniffer_size), // 32
    .probe5(sniffer_timer), // 64
    .probe6(sniffer_host_pid), // 6
    .probe7(sniffer_host_dest), // 4
    .probe8(sniffer_host_vaddr), // 48
    .probe9(sniffer_host_len), // 28
    .probe10(sq_wr.valid),
    .probe11(sq_wr.ready),
    .probe12(cq_wr.valid),
    .probe13(cq_wr.ready),
    .probe14(axis_sink_int[0].tvalid),
    .probe15(axis_sink_int[0].tready),
    .probe16(axis_sink_int[0].tlast),
    .probe17(axis_src_int[0].tvalid),
    .probe18(axis_src_int[0].tready),
    .probe19(axis_src_int[0].tlast),
    .probe20(wrote_len), // 32
    .probe21(req_sent_flg), // 1
    .probe22(outstanding_req), // 4
    .probe23(axis_sniffer_merged.tdata), // 512
    .probe24(axis_sniffer_merged.tvalid), // 1
    .probe25(axis_sniffer_merged.tready), // 1
    .probe26(axis_sniffer_merged.tkeep), // 64
    .probe27(axis_sniffer_merged.tlast), // 1
    .probe28(within_packet_not_last), // 1 
    .probe29(axis_rx_sniffer.tdata), // 512
    .probe30(axis_rx_sniffer.tvalid),
    .probe31(axis_rx_sniffer.tready),
    .probe32(axis_rx_sniffer.tkeep), // 64
    .probe33(axis_rx_sniffer.tlast),
    .probe34(axis_tx_sniffer.tdata), // 512
    .probe35(axis_tx_sniffer.tvalid),
    .probe36(axis_tx_sniffer.tready),
    .probe37(axis_tx_sniffer.tkeep), // 64
    .probe38(axis_tx_sniffer.tlast)
);
