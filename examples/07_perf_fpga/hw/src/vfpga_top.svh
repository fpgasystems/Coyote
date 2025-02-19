// Simple pipeline stages, buffering the input/output signals (not really needed, but nice to have for easier timing closure)
AXI4SR axis_in_int();
axisr_reg inst_reg_in  (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_recv[0]), .m_axis(axis_in_int));

AXI4SR axis_out_int();
axisr_reg inst_reg_out (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_out_int), .m_axis(axis_host_send[0]));

///////////////////////////////////////
//          BENCH CONTROL           //
/////////////////////////////////////
// Starting read/write operations
logic [1:0] bench_ctrl;
parameter integer START_RD = 0;
parameter integer START_WR = 1;

///////////////////////////////////////
//       COMMAND COMPLETION         //
/////////////////////////////////////
// Number of requested reads/writes; controlled by the user from software
// e.g., for latency we might do 1 and for throughput we might do 32
logic [31:0] bench_n_reps;

// Number of issued reads/writes
logic [31:0] bench_sent;

// Number of completed reads/writes
logic [31:0] bench_done;

// Asserted high when all the commands have been marked as completed
logic done_req;

///////////////////////////////////////
//         DATA COMPLETION          //
/////////////////////////////////////
// Number of incoming/outgoing AXI data streams; 
// e.g. for a message of size 4096 bytes, the valid from the AXI stream goes high eight times
// and for 32 transfers (bench_n_reps = 32) like that, there will be 256 beats
// Set from the software to avoid computing divsion on the FPGA
logic [63:0] bench_n_beats;

// Number of completed AXI beats
logic [63:0] cnt_data;

// Asserted high when all the data has been processed
logic done_data;

///////////////////////////////////////
//        READ/WRITE DATA           //
/////////////////////////////////////
// Buffer size in bytes
logic [LEN_BITS-1:0] bench_len;

// Virtual address of buffer to be read from / written to
logic [VADDR_BITS-1:0] bench_vaddr;

// Coyote thread ID (obtained in software from coyote_thread.getCtid())
logic [PID_BITS-1:0] bench_pid;

///////////////////////////////////////
//           FSM & TIMING           //
/////////////////////////////////////
// In this example, reads and writes are de-coupled;
// That is, we either read bench_n_reps time from the buffer at bench_vaddr of size bench_len
// OR we write to the buffer of size bench_len at bench_vaddr; bench_n_reps times 
logic [1:0] state_C;
typedef enum logic[1:0]  {ST_IDLE, ST_READ, ST_WRITE} state_t;

// Clock cycle counter; used for meausuring the time taken to complete bench_n_reps read/write requests
logic [63:0] bench_timer;

// The values above are set from the software and propagated to the FPGA via PCIe and XDMA in a AXI Lite interface
// The helper module parses the AXI interface to the target signals
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
                // Transition to next state if user triggered benchmark start
                state_C <= bench_ctrl[START_RD] ? ST_READ : 
                           bench_ctrl[START_WR] ? ST_WRITE : ST_IDLE;

                // Reset signals for new benchmark
                cnt_data <= 0;
                bench_sent <= 0;

                done_req <= 1'b0;
                done_data <= 1'b0;
            end
            ST_READ: begin
                // Request counter and completion
                bench_sent <= (sq_rd.valid && sq_rd.ready) ? bench_sent + 1 : bench_sent;
                done_req <= ((bench_sent == bench_n_reps - 1) && sq_rd.ready) ? 1'b1 : done_req;

                // Data counter and completion
                cnt_data <= (axis_in_int.tvalid && axis_in_int.tready) ? cnt_data + 1 : cnt_data;
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_in_int.tvalid) ? 1'b1 : done_data;

                // Transition back to IDLE if complete; otherwise continue reading
                state_C <= (done_req && done_data) ? ST_IDLE : ST_READ;
            end
            ST_WRITE: begin
                // Request counter and completion
                done_req <= ((bench_sent == bench_n_reps - 1) && sq_wr.ready) ? 1'b1 : done_req;
                bench_sent <= (sq_wr.valid && sq_wr.ready) ? bench_sent + 1 : bench_sent;

                // Data counter and completion
                cnt_data <= (axis_out_int.tvalid && axis_out_int.tready) ? cnt_data + 1 : cnt_data;
                done_data <= ((cnt_data == bench_n_beats - 1) && axis_out_int.tready) ? 1'b1 : done_data;

                // Transition back to IDLE if complete; otherwise continue writing
                state_C <= (done_req && done_data) ? ST_IDLE : ST_WRITE;
            end
        endcase

        // If the benchmark has just been triggered; set the counter to 0; otherwise increment by 1
        bench_done <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 : 
                        (cq_rd.valid || cq_wr.valid) ? bench_done + 1 : bench_done;

        // Increment the timer until the number of target reps has been reached
        bench_timer <= (bench_ctrl[START_RD] || bench_ctrl[START_WR]) ? 0 :
                        (bench_done >= bench_n_reps) ? bench_timer : bench_timer + 1;

    end
end

always_comb begin
    ///////////////////////////////
    //          READS           //
    /////////////////////////////
    // Requests
    sq_rd.data = 0;
    sq_rd.data.last = 1'b1;
    sq_rd.data.pid = bench_pid;
    sq_rd.data.len = bench_len;
    sq_rd.data.vaddr = bench_vaddr;
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.opcode = LOCAL_READ;
    sq_rd.valid = (state_C == ST_READ) && ~done_req;

    cq_rd.ready = 1'b1;

    // Data
    axis_in_int.tready = (state_C == ST_READ) && ~done_data;

    ///////////////////////////////
    //          WRITES          //
    /////////////////////////////
    // Requests
    sq_wr.data = 0;
    sq_wr.data.last = 1'b1;
    sq_wr.data.pid = bench_pid;
    sq_wr.data.len = bench_len;
    sq_wr.data.vaddr = bench_vaddr;
    sq_wr.data.strm = STRM_HOST;
    sq_wr.data.opcode = LOCAL_WRITE;
    sq_wr.valid = (state_C == ST_WRITE) && ~done_req;

    cq_wr.ready = 1'b1;

    // Data
    axis_out_int.tdata = cnt_data + 1;
    axis_out_int.tkeep = ~0;
    axis_out_int.tid   = 0;
    axis_out_int.tlast = 1'b0;
    axis_out_int.tvalid = (state_C == ST_WRITE) && ~done_data;
end

// Tie off unused interfaces
always_comb notify.tie_off_m();

// ILA for debugging
ila_perf_fpga inst_ila_perf_fpga (
    .clk(aclk),
    .probe0(bench_ctrl),                // 2
    .probe1(bench_done),                // 32
    .probe2(bench_timer),               // 64
    .probe3(bench_vaddr),               // 48
    .probe4(bench_len),                 // 28
    .probe5(bench_pid),                 // 6
    .probe6(bench_n_reps),              // 32
    .probe7(bench_n_beats),             // 64
    .probe8(done_req),                  // 1
    .probe9(done_data),                 // 1
    .probe10(cnt_data),                 // 64
    .probe11(bench_sent),               // 32
    .probe12(axis_in_int.tvalid),       // 1
    .probe13(axis_in_int.tready),       // 1
    .probe14(axis_in_int.tlast),        // 1
    .probe15(axis_out_int.tvalid),      // 1
    .probe16(axis_out_int.tready),      // 1
    .probe17(axis_out_int.tlast),       // 1
    .probe18(cq_rd.valid),              // 1
    .probe19(cq_rd.ready),              // 1
    .probe20(cq_wr.valid),              // 1
    .probe21(cq_wr.ready),              // 1
    .probe22(sq_rd.valid),              // 1
    .probe23(sq_rd.ready),              // 1
    .probe24(sq_wr.valid),              // 1
    .probe25(sq_wr.ready)               // 1
);
