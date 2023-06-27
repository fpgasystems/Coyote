// I/O
AXI4SR axis_sink_0_int ();
AXI4SR axis_src_0_int ();
AXI4SR axis_sink_1_int ();
AXI4SR axis_src_1_int ();

`ifdef EN_STRM
axisr_reg inst_reg_sink_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_0_int));
axisr_reg inst_reg_src_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_0_int), .m_axis(axis_host_0_src));
axisr_reg inst_reg_sink_1 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_1_sink), .m_axis(axis_sink_1_int));
axisr_reg inst_reg_src_1 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_1_int), .m_axis(axis_host_1_src));
`else
axisr_reg inst_reg_sink_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_0_sink), .m_axis(axis_sink_0_int));
axisr_reg inst_reg_src_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_0_int), .m_axis(axis_card_0_src));
axisr_reg inst_reg_sink_1 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_1_sink), .m_axis(axis_sink_1_int));
axisr_reg inst_reg_src_1 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_1_int), .m_axis(axis_card_1_src));
`endif

// UL
parameter integer START_RD = 0;
parameter integer START_WR = 1;

// Benchmark slave
logic [1:0] bench_ctrl;
logic [31:0] bench_done;
logic [63:0] bench_timer;
logic [VADDR_BITS-1:0] bench_vaddr;
logic [LEN_BITS-1:0] bench_len;
logic [PID_BITS-1:0] bench_pid;
logic [31:0] bench_n_reps;
logic [63:0] bench_n_beats;
logic [DEST_BITS-1:0] bench_dest;

logic done_req;
logic done_data;
logic [63:0] cnt_data;
logic [31:0] bench_sent;

typedef enum logic[1:0]  {ST_IDLE, ST_READ, ST_WRITE} state_t;
logic [1:0] state_C;

logic[15:0] cnt_rd_done;
logic[15:0] cnt_wr_done;

always_ff @(posedge aclk) begin
    if(~aresetn) begin
        cnt_rd_done <= 0;
        cnt_wr_done <= 0;
    end
    else begin
        cnt_rd_done <= bpss_rd_done.valid ? cnt_rd_done + 1 : cnt_rd_done;
        cnt_wr_done <= bpss_wr_done.valid ? cnt_wr_done + 1 : cnt_wr_done;
    end
end
 
//
// CSR
//
perf_fpga_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .bench_ctrl(bench_ctrl),
    .bench_done(bench_done),
    .bench_timer(bench_timer),
    .bench_vaddr(bench_vaddr),
    .bench_len(bench_len),
    .bench_pid(bench_pid),
    .bench_n_reps(bench_n_reps),
    .bench_n_beats(bench_n_beats),
    .bench_dest(bench_dest)
);

AXI4SR axis_sink_active ();
AXI4SR axis_src_active ();

// active interface according to bench dest
// sink
assign axis_sink_active.tvalid = (bench_dest == 0) ? axis_sink_0_int.tvalid : axis_sink_1_int.tvalid;
assign axis_sink_active.tkeep = (bench_dest == 0) ? axis_sink_0_int.tkeep : axis_sink_1_int.tkeep;
assign axis_sink_active.tlast = (bench_dest == 0) ? axis_sink_0_int.tlast : axis_sink_1_int.tlast;
assign axis_sink_active.tdata = (bench_dest == 0) ? axis_sink_0_int.tdata : axis_sink_1_int.tdata;
assign axis_sink_active.tid = (bench_dest == 0) ? axis_sink_0_int.tid : axis_sink_1_int.tid;

assign axis_sink_0_int.tready = (bench_dest == 0) ? axis_sink_active.tready : 1'b0;
assign axis_sink_1_int.tready = (bench_dest == 0) ? 1'b0 : axis_sink_active.tready;
// src
assign axis_src_0_int.tvalid = (bench_dest == 0) ? axis_src_active.tvalid : 1'b0;
assign axis_src_0_int.tkeep = axis_src_active.tkeep;
assign axis_src_0_int.tlast = axis_src_active.tlast;
assign axis_src_0_int.tdata = axis_src_active.tdata;
assign axis_src_0_int.tid = axis_src_active.tid;

assign axis_src_1_int.tvalid = (bench_dest == 0) ? 1'b0 : axis_src_active.tvalid;
assign axis_src_1_int.tkeep = axis_src_active.tkeep;
assign axis_src_1_int.tlast = axis_src_active.tlast;
assign axis_src_1_int.tdata = axis_src_active.tdata;
assign axis_src_1_int.tid = axis_src_active.tid;

assign axis_src_active.tready = (bench_dest == 0) ? axis_src_0_int.tready : axis_src_1_int.tready;


// REG
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;
        bench_sent <= 'X;
        bench_done <= 'X;
        bench_timer <= 'X;

        done_req <= 'X;
        done_data <= 'X;
        cnt_data <= 'X;
    end
    else begin
        case(state_C) 

            ST_IDLE: begin
                state_C <= bench_ctrl[START_RD] ? ST_READ : 
                           bench_ctrl[START_WR] ? ST_WRITE : ST_IDLE;

                bench_sent <= 0;

                done_req <= 1'b0;
                done_data <= 1'b0;
                cnt_data <= 0;
            end

            ST_READ: begin
                // Requests
                done_req <= ((bench_sent == bench_n_reps -1) && bpss_rd_req.ready) ? 1'b1 : done_req;
                bench_sent <= (bpss_rd_req.valid && bpss_rd_req.ready) ? bench_sent + 1 : bench_sent;

                // Data
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_sink_active.tvalid) ? 1'b1 : done_data;
                cnt_data <= (axis_sink_active.tvalid && axis_sink_active.tready) ? cnt_data + 1 : cnt_data;

                state_C <= (done_req && done_data) ? ST_IDLE : ST_READ;
            end

            ST_WRITE: begin
                // Requests
                done_req <= ((bench_sent == bench_n_reps -1) && bpss_wr_req.ready) ? 1'b1 : done_req;
                bench_sent <= (bpss_wr_req.valid && bpss_wr_req.ready) ? bench_sent + 1 : bench_sent;

                // Data
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_src_active.tready) ? 1'b1 : done_data;
                cnt_data <= (axis_src_active.tvalid && axis_src_active.tready) ? cnt_data + 1 : cnt_data;

                state_C <= (done_req && done_data) ? ST_IDLE : ST_WRITE;
            end

        endcase

        // Status
        bench_done <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 : 
                        (bpss_rd_done.valid || bpss_wr_done.valid) ? bench_done + 1 : bench_done;

        bench_timer <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 :
                        (bench_done >= bench_n_reps) ? bench_timer : bench_timer + 1;

    end
end

// DP
always_comb begin
    // Requests
    bpss_rd_req.data = 0;
    bpss_rd_req.data.vaddr = bench_vaddr;
    bpss_rd_req.data.len = bench_len;
    bpss_rd_req.data.pid = bench_pid;
    bpss_rd_req.data.ctl = 1'b1;
    bpss_rd_req.data.dest = bench_dest;
    bpss_rd_req.valid = (state_C == ST_READ) && ~done_req;

    bpss_wr_req.data = 0;
    bpss_wr_req.data.vaddr = bench_vaddr;
    bpss_wr_req.data.len = bench_len;
    bpss_wr_req.data.pid = bench_pid;
    bpss_wr_req.data.ctl = 1'b1;
    bpss_wr_req.data.dest = bench_dest;
    bpss_wr_req.valid = (state_C == ST_WRITE) && ~done_req;

    bpss_rd_done.ready = 1'b1;
    bpss_wr_done.ready = 1'b1;

    // Data
    axis_sink_active.tready = (state_C == ST_READ) && ~done_data;

    axis_src_active.tdata = cnt_data + 1;
    axis_src_active.tkeep = ~0;
    axis_src_active.tid   = 0;
    axis_src_active.tlast = 1'b0;
    axis_src_active.tvalid = (state_C == ST_WRITE) && ~done_data;
end


/*
// Debug
logic [PID_BITS-1:0] bpss_rd_done_pid;
logic bpss_rd_done_stream;
logic [DEST_BITS-1:0] bpss_rd_done_dest;
logic bpss_rd_done_host;

logic [PID_BITS-1:0] bpss_wr_done_pid;
logic bpss_wr_done_stream;
logic [DEST_BITS-1:0] bpss_wr_done_dest;
logic bpss_wr_done_host;

assign bpss_rd_done_pid = bpss_rd_done.data[PID_BITS-1:0];
assign bpss_rd_done_dest = bpss_rd_done.data[PID_BITS+DEST_BITS-1:PID_BITS];
assign bpss_rd_done_stream = bpss_rd_done.data[PID_BITS+DEST_BITS:PID_BITS+DEST_BITS];
assign bpss_rd_done_host = bpss_rd_done.data[PID_BITS+DEST_BITS+1:PID_BITS+DEST_BITS+1];

assign bpss_wr_done_pid = bpss_wr_done.data[PID_BITS-1:0];
assign bpss_wr_done_dest = bpss_wr_done.data[PID_BITS+DEST_BITS-1:PID_BITS];
assign bpss_wr_done_stream = bpss_wr_done.data[PID_BITS+DEST_BITS:PID_BITS+DEST_BITS];
assign bpss_wr_done_host = bpss_wr_done.data[PID_BITS+DEST_BITS+1:PID_BITS+DEST_BITS+1];

ila_0 inst_ila_0 (
    .clk(aclk),
    .probe0(bench_ctrl), // 2
    .probe1(bench_done), // 1
    .probe2(bench_timer), 
    .probe3(bench_vaddr),
    .probe4(bench_len), // 28
    .probe5(bench_pid), // 6
    .probe6(bench_n_reps), // 32
    .probe7(bench_n_beats), // 64
    .probe8(done_req),
    .probe9(done_data),
    .probe10(cnt_data), // 64
    .probe11(bench_sent), // 32
    .probe12(cnt_rd_done), // 16
    .probe13(cnt_wr_done), // 16
    .probe14(axis_sink_0_int.tvalid),
    .probe15(axis_sink_0_int.tready),
    .probe16(axis_sink_0_int.tlast),
    .probe17(axis_src_0_int.tvalid),
    .probe18(axis_src_0_int.tready),
    .probe19(axis_src_0_int.tlast),
    .probe20(axis_sink_1_int.tvalid),
    .probe21(axis_sink_1_int.tready),
    .probe22(axis_sink_1_int.tlast),
    .probe23(axis_src_1_int.tvalid),
    .probe24(axis_src_1_int.tready),
    .probe25(axis_src_1_int.tlast),
    .probe26(bpss_rd_done.valid),
    .probe27(bpss_rd_done_pid), //6
    .probe28(bpss_rd_done_stream), 
    .probe29(bpss_rd_done_dest), //4
    .probe30(bpss_wr_done.valid),
    .probe31(bpss_wr_done_pid), //6
    .probe32(bpss_wr_done_stream), 
    .probe33(bpss_wr_done_dest), //4
    .probe34(bench_dest), // 4
    .probe35(bpss_wr_req.valid),
    .probe36(bpss_rd_req.valid),
    .probe37(bpss_rd_done_host),
    .probe38(bpss_wr_done_host)
);
*/

