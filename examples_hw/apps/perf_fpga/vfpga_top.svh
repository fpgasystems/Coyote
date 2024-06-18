always_comb notify.tie_off_m();

// I/O
AXI4SR axis_sink_int[N_STRM_AXI]();
AXI4SR axis_src_int[N_STRM_AXI]();

`ifndef EN_MEM
for (genvar i = 0; i < N_STRM_AXI; i++) begin
    axisr_reg inst_reg_sink_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_recv[i]), .m_axis(axis_sink_int[i]));
    axisr_reg inst_reg_src_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int[i]), .m_axis(axis_host_send[i]));
end
`else
for (genvar i = 0; i < N_CARD_AXI; i++) begin
    axisr_reg inst_reg_sink_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_recv[i]), .m_axis(axis_sink_int[i]));
    axisr_reg inst_reg_src_0 (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int[i]), .m_axis(axis_card_send[i]));
end
`endif

// UL
parameter integer START_RD = 0;
parameter integer START_WR = 1;

// Benchmark slave
logic [1:0] bench_ctrl;
logic [31:0] bench_done;
logic [63:0] bench_timer;
logic [PID_BITS-1:0] bench_pid;
logic [DEST_BITS-1:0] bench_dest;
logic [VADDR_BITS-1:0] bench_vaddr;
logic [LEN_BITS-1:0] bench_len;
logic [31:0] bench_n_reps;
logic [63:0] bench_n_beats;

logic done_req;
logic done_data;
logic [63:0] cnt_data;
logic [31:0] bench_sent;

typedef enum logic[1:0]  {ST_IDLE, ST_READ, ST_WRITE} state_t;
logic [1:0] state_C;

logic[15:0] cnt_cq_rd;
logic[15:0] cnt_cq_wr;

always_ff @(posedge aclk) begin
    if(~aresetn) begin
        cnt_cq_rd <= 0;
        cnt_cq_wr <= 0;
    end
    else begin
        cnt_cq_rd <= cq_rd.valid ? cnt_cq_rd + 1 : cnt_cq_rd;
        cnt_cq_wr <= cq_wr.valid ? cnt_cq_wr + 1 : cnt_cq_wr;
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
    .bench_pid(bench_pid),
    .bench_dest(bench_dest),
    .bench_vaddr(bench_vaddr),
    .bench_len(bench_len),
    .bench_n_reps(bench_n_reps),
    .bench_n_beats(bench_n_beats)
);

AXI4SR axis_sink_active ();
AXI4SR axis_src_active ();

// active interface according to bench dest
// sink
assign axis_sink_active.tvalid = (bench_dest == 0) ? axis_sink_int[0].tvalid : axis_sink_int[1].tvalid;
assign axis_sink_active.tkeep = (bench_dest == 0) ? axis_sink_int[0].tkeep : axis_sink_int[1].tkeep;
assign axis_sink_active.tlast = (bench_dest == 0) ? axis_sink_int[0].tlast : axis_sink_int[1].tlast;
assign axis_sink_active.tdata = (bench_dest == 0) ? axis_sink_int[0].tdata : axis_sink_int[1].tdata;
assign axis_sink_active.tid = (bench_dest == 0) ? axis_sink_int[0].tid : axis_sink_int[1].tid;

assign axis_sink_int[0].tready = (bench_dest == 0) ? axis_sink_active.tready : 1'b0;
assign axis_sink_int[1].tready = (bench_dest == 0) ? 1'b0 : axis_sink_active.tready;
// src
assign axis_src_int[0].tvalid = (bench_dest == 0) ? axis_src_active.tvalid : 1'b0;
assign axis_src_int[0].tkeep = axis_src_active.tkeep;
assign axis_src_int[0].tlast = axis_src_active.tlast;
assign axis_src_int[0].tdata = axis_src_active.tdata;
assign axis_src_int[0].tid = axis_src_active.tid;

assign axis_src_int[1].tvalid = (bench_dest == 0) ? 1'b0 : axis_src_active.tvalid;
assign axis_src_int[1].tkeep = axis_src_active.tkeep;
assign axis_src_int[1].tlast = axis_src_active.tlast;
assign axis_src_int[1].tdata = axis_src_active.tdata;
assign axis_src_int[1].tid = axis_src_active.tid;

assign axis_src_active.tready = (bench_dest == 0) ? axis_src_int[0].tready : axis_src_int[1].tready;

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
    end else begin
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
                done_req <= ((bench_sent == bench_n_reps -1) && sq_rd.ready) ? 1'b1 : done_req;
                bench_sent <= (sq_rd.valid && sq_rd.ready) ? bench_sent + 1 : bench_sent;

                // Data
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_sink_active.tvalid) ? 1'b1 : done_data;
                cnt_data <= (axis_sink_active.tvalid && axis_sink_active.tready) ? cnt_data + 1 : cnt_data;

                state_C <= (done_req && done_data) ? ST_IDLE : ST_READ;
            end
            ST_WRITE: begin
                // Requests
                done_req <= ((bench_sent == bench_n_reps -1) && sq_wr.ready) ? 1'b1 : done_req;
                bench_sent <= (sq_wr.valid && sq_wr.ready) ? bench_sent + 1 : bench_sent;

                // Data
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_src_active.tready) ? 1'b1 : done_data;
                cnt_data <= (axis_src_active.tvalid && axis_src_active.tready) ? cnt_data + 1 : cnt_data;

                state_C <= (done_req && done_data) ? ST_IDLE : ST_WRITE;
            end
        endcase

        // Status
        bench_done <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 : 
                        (cq_rd.valid || cq_wr.valid) ? bench_done + 1 : bench_done;

        bench_timer <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 :
                        (bench_done >= bench_n_reps) ? bench_timer : bench_timer + 1;

    end
end

// DP
always_comb begin
    // Requests
    sq_rd.data = 0;
    sq_rd.data.opcode = 5'd1;
    sq_rd.data.strm = 2'b0;
    sq_rd.data.mode = 0;
    sq_rd.data.rdma = 0;
    sq_rd.data.remote = 0;
    sq_rd.data.pid = bench_pid;
    sq_rd.data.dest = bench_dest;
    sq_rd.data.last = 1'b1;
    sq_rd.data.vaddr = bench_vaddr;
    sq_rd.data.len = bench_len;
    sq_rd.valid = (state_C == ST_READ) && ~done_req;

    sq_wr.data = 0;
    sq_wr.data.opcode = 5'd2;
    sq_wr.data.strm = 2'b0;
    sq_wr.data.mode = 0;
    sq_wr.data.rdma = 0;
    sq_wr.data.remote = 0;
    sq_wr.data.pid = bench_pid;
    sq_wr.data.dest = bench_dest;
    sq_wr.data.last = 1'b1;
    sq_wr.data.vaddr = bench_vaddr;
    sq_wr.data.len = bench_len;
    sq_wr.valid = (state_C == ST_WRITE) && ~done_req;

    cq_rd.ready = 1'b1;
    cq_wr.ready = 1'b1;

    // Data
    axis_sink_active.tready = (state_C == ST_READ) && ~done_data;

    axis_src_active.tdata = cnt_data + 1;
    axis_src_active.tkeep = ~0;
    axis_src_active.tid   = 0;
    axis_src_active.tlast = 1'b0;
    axis_src_active.tvalid = (state_C == ST_WRITE) && ~done_data;
end

// Debug

ila_perf_fpga inst_ila_perf_fpga (
    .clk(aclk),
    .probe0(bench_ctrl), // 2
    .probe1(bench_done), // 1
    .probe2(bench_timer), // 64
    .probe3(bench_vaddr), // 48
    .probe4(bench_len), // 28
    .probe5(bench_pid), // 6
    .probe6(bench_n_reps), // 32
    .probe7(bench_n_beats), // 64
    .probe8(done_req),
    .probe9(done_data),
    .probe10(cnt_data), // 64
    .probe11(bench_sent), // 32
    .probe12(cnt_cq_rd), // 16
    .probe13(cnt_cq_wr), // 16
    .probe14(axis_sink_int[0].tvalid),
    .probe15(axis_sink_int[0].tready),
    .probe16(axis_sink_int[0].tlast),
    .probe17(axis_src_int[0].tvalid),
    .probe18(axis_src_int[0].tready),
    .probe19(axis_src_int[0].tlast),
    .probe20(axis_sink_int[1].tvalid),
    .probe21(axis_sink_int[1].tready),
    .probe22(axis_sink_int[1].tlast),
    .probe23(axis_src_int[1].tvalid),
    .probe24(axis_src_int[1].tready),
    .probe25(axis_src_int[1].tlast),
    .probe26(cq_rd.valid),
    .probe27(cq_rd.data.pid), // 6
    .probe28(cq_rd.data.host), 
    .probe29(cq_rd.data.dest), // 4
    .probe30(cq_wr.valid),
    .probe31(cq_wr.pid), // 6
    .probe32(cq_wr.host), 
    .probe33(cq_wr.dest), // 4
    .probe34(bench_dest), // 4
    .probe35(sq_wr.valid),
    .probe36(sq_rd.valid)
);
