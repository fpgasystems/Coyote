// I/O
AXI4SR axis_sink_int ();
AXI4SR axis_src_int ();

`ifdef EN_STRM
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_sink), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_host_src));
`else
axisr_reg inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_card_sink), .m_axis(axis_sink_int));
axisr_reg inst_reg_src (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_src_int), .m_axis(axis_card_src));
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
bmark_slave inst_slave (
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
    .bench_n_beats(bench_n_beats)
);

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
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_sink_int.tvalid) ? 1'b1 : done_data;
                cnt_data <= (axis_sink_int.tvalid && axis_sink_int.tready) ? cnt_data + 1 : cnt_data;

                state_C <= (done_req && done_data) ? ST_IDLE : ST_READ;
            end

            ST_WRITE: begin
                // Requests
                done_req <= ((bench_sent == bench_n_reps -1) && bpss_wr_req.ready) ? 1'b1 : done_req;
                bench_sent <= (bpss_wr_req.valid && bpss_wr_req.ready) ? bench_sent + 1 : bench_sent;

                // Data
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_src_int.tready) ? 1'b1 : done_data;
                cnt_data <= (axis_src_int.tvalid && axis_src_int.tready) ? cnt_data + 1 : cnt_data;

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
    bpss_rd_req.valid = (state_C == ST_READ) && ~done_req;

    bpss_wr_req.data = 0;
    bpss_wr_req.data.vaddr = bench_vaddr;
    bpss_wr_req.data.len = bench_len;
    bpss_wr_req.data.pid = bench_pid;
    bpss_wr_req.data.ctl = 1'b1;
    bpss_wr_req.valid = (state_C == ST_WRITE) && ~done_req;

    bpss_rd_done.ready = 1'b1;
    bpss_wr_done.ready = 1'b1;

    // Data
    axis_sink_int.tready = (state_C == ST_READ) && ~done_data;

    axis_src_int.tdata = cnt_data + 1;
    axis_src_int.tkeep = ~0;
    axis_src_int.tid   = 0;
    axis_src_int.tlast = 1'b0;
    axis_src_int.tvalid = (state_C == ST_WRITE) && ~done_data;
end