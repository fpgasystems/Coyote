// nodbg variant of A05_perf_fpga — ILA (ila_perf_fpga) removed
// Added stream[1] tie-offs for N_STRM_AXI=2 shell.

// Simple pipeline stages
AXI4SR axis_in_int (.*);
axisr_reg inst_reg_in  (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_recv[0]), .m_axis(axis_in_int));

AXI4SR axis_out_int (.*);
axisr_reg inst_reg_out (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_out_int), .m_axis(axis_host_send[0]));

///////////////////////////////////////
//          BENCH CONTROL           //
/////////////////////////////////////
logic [1:0] bench_ctrl;
parameter integer START_RD = 0;
parameter integer START_WR = 1;

///////////////////////////////////////
//       COMMAND COMPLETION         //
/////////////////////////////////////
logic [31:0] bench_n_reps;
logic [31:0] bench_sent;
logic [31:0] bench_done;
logic done_req;

///////////////////////////////////////
//         DATA COMPLETION          //
/////////////////////////////////////
logic [63:0] bench_n_beats;
logic [63:0] cnt_data;
logic done_data;

///////////////////////////////////////
//        READ/WRITE DATA           //
/////////////////////////////////////
logic [LEN_BITS-1:0] bench_len;
logic [VADDR_BITS-1:0] bench_vaddr;
logic [PID_BITS-1:0] bench_pid;

///////////////////////////////////////
//           FSM & TIMING           //
/////////////////////////////////////
logic [1:0] state_C;
typedef enum logic[1:0]  {ST_IDLE, ST_READ, ST_WRITE} state_t;
logic [63:0] bench_timer;

perf_fpga_axi_ctrl_parser inst_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .bench_ctrl(bench_ctrl),
    .bench_done(bench_done),
    .bench_timer(bench_timer),
    .bench_pid(bench_pid),
    .bench_vaddr(bench_vaddr),
    .bench_len(bench_len),
    .bench_n_reps(bench_n_reps),
    .bench_n_beats(bench_n_beats)
);

// State-machine transition and counters
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        state_C <= ST_IDLE;
        cnt_data <= 0;
        bench_sent <= 0;

        done_req <= 1'b0;
        done_data <= 1'b0;

        bench_done <= 0;
        bench_timer <= 'X;
    end
    else begin
        case(state_C)
            ST_IDLE: begin
                state_C <= bench_ctrl[START_RD] ? ST_READ :
                           bench_ctrl[START_WR] ? ST_WRITE : ST_IDLE;
                cnt_data <= 0;
                bench_sent <= 0;
                done_req <= 1'b0;
                done_data <= 1'b0;
            end
            ST_READ: begin
                bench_sent <= (sq_rd.valid && sq_rd.ready) ? bench_sent + 1 : bench_sent;
                done_req <= ((bench_sent == bench_n_reps - 1) && sq_rd.ready) ? 1'b1 : done_req;
                cnt_data <= (axis_in_int.tvalid && axis_in_int.tready) ? cnt_data + 1 : cnt_data;
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_in_int.tvalid) ? 1'b1 : done_data;
                state_C <= (done_req && done_data) ? ST_IDLE : ST_READ;
            end
            ST_WRITE: begin
                done_req <= ((bench_sent == bench_n_reps - 1) && sq_wr.ready) ? 1'b1 : done_req;
                bench_sent <= (sq_wr.valid && sq_wr.ready) ? bench_sent + 1 : bench_sent;
                cnt_data <= (axis_out_int.tvalid && axis_out_int.tready) ? cnt_data + 1 : cnt_data;
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_out_int.tready) ? 1'b1 : done_data;
                state_C <= (done_req && done_data) ? ST_IDLE : ST_WRITE;
            end
        endcase

        bench_done <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 :
                      (cq_rd.valid || cq_wr.valid) ? 1 : bench_done;
        bench_timer <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 :
                        bench_done ? bench_timer : bench_timer + 1;
    end
end

always_comb begin
    // READS
    sq_rd.data = 0;
    sq_rd.data.last = bench_sent == bench_n_reps - 1;
    sq_rd.data.pid = bench_pid;
    sq_rd.data.len = bench_len;
    sq_rd.data.vaddr = bench_vaddr;
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.opcode = LOCAL_READ;
    sq_rd.valid = (state_C == ST_READ) && ~done_req;

    cq_rd.ready = 1'b1;

    axis_in_int.tready = (state_C == ST_READ) && ~done_data;

    // WRITES
    sq_wr.data = 0;
    sq_wr.data.last = bench_sent == bench_n_reps - 1;
    sq_wr.data.pid = bench_pid;
    sq_wr.data.len = bench_len;
    sq_wr.data.vaddr = bench_vaddr;
    sq_wr.data.strm = STRM_HOST;
    sq_wr.data.opcode = LOCAL_WRITE;
    sq_wr.valid = (state_C == ST_WRITE) && ~done_req;

    cq_wr.ready = 1'b1;

    axis_out_int.tdata = cnt_data + 1;
    axis_out_int.tkeep = ~0;
    axis_out_int.tid   = 0;
    axis_out_int.tlast = cnt_data == bench_n_beats - 1;
    axis_out_int.tvalid = (state_C == ST_WRITE) && ~done_data;
end

// Tie-off unused stream[1] (shell has N_STRM_AXI=2)
always_comb axis_host_recv[1].tie_off_s();
always_comb axis_host_send[1].tie_off_m();

// Tie off unused interfaces
always_comb notify.tie_off_m();

