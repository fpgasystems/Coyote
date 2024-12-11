`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module test_top (
    // AXI4L CONTROL
    AXI4L.s                     axi_ctrl,

    // NOTIFY
    metaIntf.m                  notify,

    // DESCRIPTORS
    metaIntf.m                  sq_rd,
    metaIntf.m                  sq_wr,
    metaIntf.s                  cq_rd,
    metaIntf.s                  cq_wr,

    // HOST DATA STREAMS
    AXI4SR.s                    axis_host_recv [N_STRM_AXI],
    AXI4SR.m                    axis_host_send [N_STRM_AXI],

    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn
);

    // tieoffs
    always_comb notify.tie_off_m();
    //always_comb sq_wr.tie_off_m();
    //always_comb axis_host_send[0].tie_off_m();
    //always_comb axis_host_send[1].tie_off_m();

    localparam integer N_REGS = 16;
    localparam integer ADDR_LSB = 3;
    localparam integer ADDR_MSB = 8;

    localparam integer REG_READ_ARGS_0 = 0;
    localparam integer REG_READ_ARGS_1 = 1;
    localparam integer REG_READ_VADDR_0 = 2;
    localparam integer REG_READ_VADDR_1 = 3;
    localparam integer REG_READ_LEN_0 = 4;
    localparam integer REG_READ_LEN_1 = 5;
    localparam integer REG_WRITE_ARGS_0 = 6;
    localparam integer REG_WRITE_ARGS_1 = 7;
    localparam integer REG_WRITE_VADDR_0 = 8;
    localparam integer REG_WRITE_VADDR_1 = 9;
    localparam integer REG_WRITE_LEN_0 = 10;
    localparam integer REG_WRITE_LEN_1 = 11;

    localparam byte STATE_IDLE = 0;         // Waiting for the transfer to start
    localparam byte STATE_REQ_0 = 1;        // First read/write request
    localparam byte STATE_REQ_WAIT_0 = 2;   // Wait for first read/write request
    localparam byte STATE_REQ_1 = 3;        // Second read/write request
    localparam byte STATE_REQ_DONE = 4;     // Wait for second read/write request
    localparam byte STATE_COPY = 5;         // wait for copy to finish

    // signals
    logic [ADDR_MSB-1:0] axi_ctrl_awaddr;
    logic [ADDR_MSB-1:0] axi_ctrl_araddr;
    logic ctrl_arready;
    logic ctrl_awready;
    logic ctrl_bvalid;
    logic ctrl_wready;
    logic ctrl_rvalid;
    logic [1:0] ctrl_rresp;
    logic [63:0] ctrl_rdata;
    logic sq_rd_valid;
    logic sq_wr_valid;

    // control registers
    logic [63:0] latch_read_args0;
    logic [63:0] latch_read_args1;
    logic [63:0] latch_read_vaddr0;
    logic [63:0] latch_read_vaddr1;
    logic [63:0] latch_read_len0;
    logic [63:0] latch_read_len1;
    logic [63:0] latch_write_args0;
    logic [63:0] latch_write_args1;
    logic [63:0] latch_write_vaddr0;
    logic [63:0] latch_write_vaddr1;
    logic [63:0] latch_write_len0;
    logic [63:0] latch_write_len1;

    logic [63:0] read_args0;
    logic [63:0] read_args1;
    logic [63:0] read_vaddr0;
    logic [63:0] read_vaddr1;
    logic [63:0] read_len0;
    logic [63:0] read_len1;
    logic [63:0] write_args0;
    logic [63:0] write_args1;
    logic [63:0] write_vaddr0;
    logic [63:0] write_vaddr1;
    logic [63:0] write_len0;
    logic [63:0] write_len1;

    logic [7:0] state = STATE_IDLE;
    logic start_flag = 0;
    logic stall_transfer = 0;
    logic [15:0] tlast_count = 0;
    logic channel_0_last;
    logic channel_1_last;

    assign channel_0_last = axis_host_recv[0].tready & axis_host_recv[0].tvalid & axis_host_recv[0].tlast;
    assign channel_1_last = axis_host_recv[1].tready & axis_host_recv[1].tvalid & axis_host_recv[1].tlast;

    // assignments
    assign axi_ctrl_awaddr = axi_ctrl.awaddr[ADDR_MSB+ADDR_LSB-1:ADDR_LSB];
    assign axi_ctrl_araddr = axi_ctrl.araddr[ADDR_MSB+ADDR_LSB-1:ADDR_LSB];

    assign cq_rd.ready = 1;
    assign cq_wr.ready = 1;

    assign axis_host_recv[0].tready = axis_host_send[0].tready;
    assign axis_host_send[0].tvalid = axis_host_recv[0].tvalid;
    assign axis_host_send[0].tkeep = axis_host_recv[0].tkeep;
    assign axis_host_send[0].tdata = axis_host_recv[0].tdata;
    assign axis_host_send[0].tlast = axis_host_recv[0].tlast;

    // second stream has special ready handling and is done below

    assign axi_ctrl.arready = ctrl_arready;
    assign axi_ctrl.awready = ctrl_awready;
    assign axi_ctrl.bvalid = ctrl_bvalid;
    assign axi_ctrl.wready = ctrl_wready;
    assign axi_ctrl.rvalid = ctrl_rvalid;
    assign axi_ctrl.rresp = ctrl_rresp;
    assign axi_ctrl.rdata = ctrl_rdata;

    assign sq_rd.valid = sq_rd_valid;
    assign sq_wr.valid = sq_wr_valid;

    // State Machine
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            tlast_count <= 0;
            stall_transfer <= 0;
            state <= STATE_IDLE;
            axis_host_recv[1].tready <= 0;
            axis_host_send[1].tvalid <= 0;
            sq_rd_valid <= 0;
            sq_rd.data <= 0;
            sq_wr_valid <= 0;
            sq_wr.data <= 0;
            read_vaddr0 <= 0;
            read_vaddr1 <= 0;
            read_len0 <= 0;
            read_len1 <= 0;
            read_args0 <= 0;
            read_args1 <= 0;
            write_vaddr0 <= 0;
            write_vaddr1 <= 0;
            write_len0 <= 0;
            write_len1 <= 0;
            write_args0 <= 0;
            write_args1 <= 0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                        if (start_flag) begin
                            state <= STATE_REQ_0;
                            tlast_count <= 0;

                            // latch the control registers
                            read_vaddr0 <= latch_read_vaddr0;
                            read_vaddr1 <= latch_read_vaddr1;
                            read_len0 <= latch_read_len0;
                            read_len1 <= latch_read_len1;
                            read_args0 <= latch_read_args0;
                            read_args1 <= latch_read_args1;

                            write_vaddr0 <= latch_write_vaddr0;
                            write_vaddr1 <= latch_write_vaddr1;
                            write_len0 <= latch_write_len0;
                            write_len1 <= latch_write_len1;
                            write_args0 <= latch_write_args0;
                            write_args1 <= latch_write_args1;

                            // select for stalling the second transfer
                            stall_transfer <= latch_read_args0[56];
                        end
                    end
                STATE_REQ_0: begin
                        // write the read request
                        sq_rd.data.vaddr <= read_vaddr0[47:0]; // virtual address in dedicated register
                        sq_rd.data.len <= read_len0[27:0]; // length in dedicated register
                        sq_rd.data.last <= 1; // this is mandatory

                        // handle additional arguments passed in the args register
                        sq_rd.data.opcode <= read_args0[4:0];    // byte 0
                        sq_rd.data.strm <= read_args0[9:8];      // byte 1
                        sq_rd.data.mode <= read_args0[16];       // byte 2
                        sq_rd.data.rdma <= read_args0[24];       // byte 3
                        sq_rd.data.remote <= read_args0[32];     // byte 4
                        sq_rd.data.pid <= read_args0[46:40];     // byte 5
                        sq_rd.data.dest <= read_args0[51:48];    // byte 6

                        // write the write request
                        sq_wr.data.vaddr <= write_vaddr0[47:0]; // virtual address in dedicated register
                        sq_wr.data.len <= write_len0[27:0]; // length in dedicated register
                        sq_wr.data.last <= 1; // this is mandatory

                        // handle additional arguments passed in the args register
                        sq_wr.data.opcode <= write_args0[4:0];    // byte 0
                        sq_wr.data.strm <= write_args0[9:8];      // byte 1
                        sq_wr.data.mode <= write_args0[16];       // byte 2
                        sq_wr.data.rdma <= write_args0[24];       // byte 3
                        sq_wr.data.remote <= write_args0[32];     // byte 4
                        sq_wr.data.pid <= write_args0[46:40];     // byte 5
                        sq_wr.data.dest <= write_args0[51:48];    // byte 6

                        sq_rd_valid <= 1;
                        sq_wr_valid <= 1;
                        state <= STATE_REQ_WAIT_0;
                    end
                STATE_REQ_WAIT_0: begin
                        // wait for both the requests to be transferred and clear them
                        if (sq_rd_valid && sq_rd.ready) begin
                            sq_rd_valid <= 0;
                            sq_rd.data <= 0;
                        end
                        if (sq_wr_valid && sq_wr.ready) begin
                            sq_wr_valid <= 0;
                            sq_wr.data <= 0;
                        end
                        // if both have been seen, transition to next state
                        if (sq_rd_valid && sq_rd.ready && sq_wr_valid && sq_wr.ready) begin
                            state <= STATE_REQ_1;
                        end
                        else if (~sq_rd_valid && sq_wr_valid && sq_wr.ready) begin
                            state <= STATE_REQ_1;
                        end
                        else if (~sq_wr_valid && sq_rd_valid && sq_rd.ready) begin
                            state <= STATE_REQ_1;
                        end
                        else if (~sq_rd_valid && ~sq_wr_valid) begin
                            state <= STATE_REQ_1;
                        end
                    end
                STATE_REQ_1: begin
                        // write the read request
                        sq_rd.data.vaddr <= read_vaddr1[47:0]; // virtual address in dedicated register
                        sq_rd.data.len <= read_len1[27:0]; // length in dedicated register
                        sq_rd.data.last <= 1; // this is mandatory

                        // handle additional arguments passed in the args register
                        sq_rd.data.opcode <= read_args1[4:0];    // byte 0
                        sq_rd.data.strm <= read_args1[9:8];      // byte 1
                        sq_rd.data.mode <= read_args1[16];       // byte 2
                        sq_rd.data.rdma <= read_args1[24];       // byte 3
                        sq_rd.data.remote <= read_args1[32];     // byte 4
                        sq_rd.data.pid <= read_args1[46:40];     // byte 5
                        sq_rd.data.dest <= read_args1[51:48];    // byte 6

                        // write the write request
                        sq_wr.data.vaddr <= write_vaddr1[47:0]; // virtual address in dedicated register
                        sq_wr.data.len <= write_len1[27:0]; // length in dedicated register
                        sq_wr.data.last <= 1; // this is mandatory

                        // handle additional arguments passed in the args register
                        sq_wr.data.opcode <= write_args1[4:0];    // byte 0
                        sq_wr.data.strm <= write_args1[9:8];      // byte 1
                        sq_wr.data.mode <= write_args1[16];       // byte 2
                        sq_wr.data.rdma <= write_args1[24];       // byte 3
                        sq_wr.data.remote <= write_args1[32];     // byte 4
                        sq_wr.data.pid <= write_args1[46:40];     // byte 5
                        sq_wr.data.dest <= write_args1[51:48];    // byte 6

                        sq_rd_valid <= 1;
                        sq_wr_valid <= 1;
                        state <= STATE_REQ_DONE;
                    end
                STATE_REQ_DONE: begin
                        // wait for both the requests to be transferred and clear them
                        if (sq_rd_valid && sq_rd.ready) begin
                            sq_rd_valid <= 0;
                            sq_rd.data <= 0;
                        end
                        if (sq_wr_valid && sq_wr.ready) begin
                            sq_wr_valid <= 0;
                            sq_wr.data <= 0;
                        end
                        // if both have been seen, transition to next state
                        if (sq_rd_valid && sq_rd.ready && sq_wr_valid && sq_wr.ready) begin
                            state <= STATE_COPY;
                        end
                        else if (~sq_rd_valid && sq_wr_valid && sq_wr.ready) begin
                            state <= STATE_COPY;
                        end
                        else if (~sq_wr_valid && sq_rd_valid && sq_rd.ready) begin
                            state <= STATE_COPY;
                        end
                        else if (~sq_rd_valid && ~sq_wr_valid) begin
                            state <= STATE_COPY;
                        end
                    end
                STATE_COPY: begin
                        // wait for two tlast signals
                        if (tlast_count + unsigned'(channel_0_last) + unsigned'(channel_1_last) == unsigned'(2)) begin
                            state <= STATE_IDLE;
                        end
                        else begin
                            tlast_count <= tlast_count + unsigned'(channel_0_last) + unsigned'(channel_1_last);
                        end
                        // ready for second transfer
                        if (channel_0_last) begin
                            stall_transfer <= 0;
                        end
                        // handle tready and tvalid of axis_host_recv[1]
                        // this is all done here for better consistency
                        // TODO: this needs to happen with better control, for better timing
                        if (stall_transfer == 1'b0) begin
                            axis_host_recv[1].tready <= axis_host_send[1].tready;
                            axis_host_send[1].tvalid <= axis_host_recv[1].tvalid;
                            axis_host_send[1].tkeep <= axis_host_recv[1].tkeep;
                            axis_host_send[1].tdata <= axis_host_recv[1].tdata;
                            axis_host_send[1].tlast <= axis_host_recv[1].tlast;
                        end
                        else begin
                            axis_host_recv[1].tready <= 0;
                            axis_host_send[1].tvalid <= 0;
                            axis_host_send[1].tkeep <= 0;
                            axis_host_send[1].tdata <= 0;
                            axis_host_send[1].tlast <= 0;
                        end
                    end
                default:
                    $display("This should never happen!");
            endcase
            // axi_ctrl write communication (ignored when not in STATE_IDLE)
            // This needs to be handled at all times, or the system will lock up
        end
    end

    // handle reading from ctrl registers
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // reset control registers and state
            ctrl_arready <= 0;
            ctrl_rvalid <= 0;
            ctrl_rresp <= 0;
            ctrl_rdata <= 0;
            ctrl_awready <= 0;
            ctrl_bvalid <= 0;
            ctrl_wready <= 0;
            axi_ctrl.bresp <= 0;
            latch_read_vaddr0 <= 0;
            latch_read_vaddr1 <= 0;
            latch_read_len0 <= 0;
            latch_read_len1 <= 0;
            latch_read_args0 <= 0;
            latch_read_args1 <= 0;
            latch_write_vaddr0 <= 0;
            latch_write_vaddr1 <= 0;
            latch_write_len0 <= 0;
            latch_write_len1 <= 0;
            latch_write_args0 <= 0;
            latch_write_args1 <= 0;
            start_flag <= 0;
        end else begin
            // handle axi_ctrl writes
            if (ctrl_awready && axi_ctrl.awvalid && ctrl_wready && axi_ctrl.wvalid) begin
                case (axi_ctrl_awaddr)
                    REG_READ_ARGS_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_args0 <= axi_ctrl.wdata;
                            start_flag <= 1; // start the transfer
                        end
                    end
                    REG_READ_ARGS_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_args1 <= axi_ctrl.wdata;
                        end
                    end
                    REG_READ_VADDR_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_vaddr0 <= axi_ctrl.wdata;
                        end
                    end
                    REG_READ_VADDR_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_vaddr1 <= axi_ctrl.wdata;
                        end
                    end
                    REG_READ_LEN_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_len0 <= axi_ctrl.wdata;
                        end
                    end
                    REG_READ_LEN_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_read_len1 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_ARGS_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_args0 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_ARGS_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_args1 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_VADDR_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_vaddr0 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_VADDR_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_vaddr1 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_LEN_0: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_len0 <= axi_ctrl.wdata;
                        end
                    end
                    REG_WRITE_LEN_1: begin
                        if (axi_ctrl.wstrb == 8'hff) begin
                            latch_write_len1 <= axi_ctrl.wdata;
                        end
                    end
                    default:
                        $display("This shouldn't happen");
                endcase
            end
            else begin
                start_flag <= 0;
            end
            // handle axi_ctrl reads
            if (ctrl_arready && axi_ctrl.arvalid) begin
                case (axi_ctrl_araddr)
                    REG_READ_ARGS_0: begin
                        ctrl_rdata[55:0] <= read_args0[55:0];
                        ctrl_rdata[63:56] <= state; // additionally add the state register here
                    end
                    REG_READ_ARGS_1: begin
                        ctrl_rdata <= read_args1;
                    end
                    REG_READ_VADDR_0: begin
                        ctrl_rdata <= read_vaddr0;
                    end
                    REG_READ_VADDR_1: begin
                        ctrl_rdata <= read_vaddr1;
                    end
                    REG_READ_LEN_0: begin
                        ctrl_rdata <= read_len0;
                    end
                    REG_READ_LEN_1: begin
                        ctrl_rdata <= read_len1;
                    end
                    REG_WRITE_ARGS_0: begin
                        ctrl_rdata <= write_args0;
                    end
                    REG_WRITE_ARGS_1: begin
                        ctrl_rdata <= write_args1;
                    end
                    REG_WRITE_VADDR_0: begin
                        ctrl_rdata <= write_vaddr0;
                    end
                    REG_WRITE_VADDR_1: begin
                        ctrl_rdata <= write_vaddr1;
                    end
                    REG_WRITE_LEN_0: begin
                        ctrl_rdata <= write_len0;
                    end
                    REG_WRITE_LEN_1: begin
                        ctrl_rdata <= write_len1;
                    end
                    default:
                        $display("This shouldn't happen");
                endcase
                // always acknowledge
                ctrl_rvalid <= 1;
                ctrl_rresp <= 0;
            end
            // handle AW ready
            if (axi_ctrl.awvalid && ~ctrl_awready) begin
                ctrl_awready <= 1;
            end
            else begin
                ctrl_awready <= 0;
            end
            // handle W ready
            if (axi_ctrl.wvalid && ~ctrl_wready) begin
                ctrl_wready <= 1;
            end
            else begin
                ctrl_wready <= 0;
            end
            // handle AR ready
            if (axi_ctrl.arvalid && ~ctrl_arready) begin
                ctrl_arready <= 1;
            end
            else begin
                ctrl_arready <= 0;
            end
            // handle R valid
            if (axi_ctrl.rready && ctrl_rvalid) begin
                ctrl_rvalid <= 0;
            end

            // handle B valid
            if (ctrl_awready && axi_ctrl.awvalid && ctrl_wready && axi_ctrl.wvalid) begin
                // always acknowledge
                axi_ctrl.bresp <= 0;
                ctrl_bvalid <= 1;
            end
            if (axi_ctrl.bready && ctrl_bvalid) begin
                ctrl_bvalid <= 0;
            end
        end
    end


endmodule
