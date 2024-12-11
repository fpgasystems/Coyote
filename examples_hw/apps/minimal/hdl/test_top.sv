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
    always_comb sq_wr.tie_off_m();
    //always_comb axis_host_send[0].tie_off_m();
    always_comb axis_host_send[1].tie_off_m();

    localparam integer N_REGS = 3;
    localparam integer ADDR_LSB = 3;
    localparam integer ADDR_MSB = 8;

    localparam integer REG_ARGS = 0;
    localparam integer REG_VADDR = 1;
    localparam integer REG_LEN = 2;

    localparam byte STATE_IDLE = 0;
    localparam byte STATE_REQ = 1;
    localparam byte STATE_REQ_DONE = 2;
    localparam byte STATE_COPY = 3;

    // signals
    logic [ADDR_MSB-1:0] axi_ctrl_awaddr;
    logic [ADDR_MSB-1:0] axi_ctrl_araddr;
    logic ctrl_arready;
    logic ctrl_awready;
    logic ctrl_bvalid;
    logic [1:0] ctrl_bresp;
    logic ctrl_wready;
    logic ctrl_rvalid;
    logic [1:0] ctrl_rresp;
    logic [63:0] ctrl_rdata;
    logic sq_rd_valid;

    // control registers
    logic [63:0] args;
    logic [63:0] vaddr;
    logic [63:0] len;

    logic [7:0] state = STATE_IDLE;

    assign axis_host_send[0].tvalid = 0;
    assign axis_host_send[0].tkeep = 0;
    assign axis_host_send[0].tdata = unsigned'(state);

    // assignments
    assign axi_ctrl_awaddr = axi_ctrl.awaddr[ADDR_MSB+ADDR_LSB-1:ADDR_LSB];
    assign axi_ctrl_araddr = axi_ctrl.araddr[ADDR_MSB+ADDR_LSB-1:ADDR_LSB];

    assign cq_rd.ready = 1;
    assign cq_wr.ready = 1;

    assign axis_host_recv[0].tready = 1;
    assign axis_host_recv[1].tready = 1;

    assign ctrl_arready = axi_ctrl.arready;
    assign ctrl_awready = axi_ctrl.awready;
    assign ctrl_bvalid = axi_ctrl.bvalid;
    assign ctrl_bresp = axi_ctrl.bresp;
    assign ctrl_wready = axi_ctrl.wready;
    assign ctrl_rvalid = axi_ctrl.rvalid;
    assign ctrl_rresp = axi_ctrl.rresp;
    assign ctrl_rdata = axi_ctrl.rdata;

    assign sq_rd_valid = sq_rd.valid;

    // read from the axi_ctrl_interface
    function automatic read_from_ctrl(
        input logic [63:0] data,
        input logic [7:0] strb,
        output logic [63:0] dest
    );
        for (int i = 0; i < 8; i++)
            dest[(i*8)+:8] <= data[(i*8)+:8] & 8'(signed'(strb[i]));
    endfunction

    // State Machine
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            ctrl_awready <= 0;
            ctrl_bvalid <= 0;
            ctrl_bresp <= 0;
            ctrl_wready <= 0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                        // handle axi_ctrl writes
                        if (ctrl_awready && axi_ctrl.awvalid && ctrl_wready && axi_ctrl.wvalid) begin
                            case (axi_ctrl_awaddr)
                                REG_ARGS: begin
                                    read_from_ctrl(axi_ctrl.wdata, axi_ctrl.wstrb, args);
                                    // only start a transaction if there was an effective transfer
                                    if (axi_ctrl.wstrb == 8'hff) begin
                                        state <= STATE_REQ;
                                    end
                                end
                                REG_VADDR: begin
                                    read_from_ctrl(axi_ctrl.wdata, axi_ctrl.wstrb, vaddr);
                                end
                                REG_LEN: begin
                                    read_from_ctrl(axi_ctrl.wdata, axi_ctrl.wstrb, len);
                                end
                                default:
                                    $display("This shouldn't happen");
                            endcase
                        end
                    end
                STATE_REQ: begin
                        // write the request
                        sq_rd.data.vaddr <= vaddr[47:0]; // virtual address in dedicated register
                        sq_rd.data.len <= len[27:0]; // length in dedicated register
                        sq_rd.data.last <= 1; // this is mandatory

                        // handle additional arguments passed in the args register
                        sq_rd.data.opcode <= args[4:0];    // byte 0
                        sq_rd.data.strm <= args[9:8];      // byte 1
                        sq_rd.data.mode <= args[16];       // byte 2
                        sq_rd.data.rdma <= args[24];       // byte 3
                        sq_rd.data.remote <= args[32];     // byte 4
                        sq_rd.data.pid <= args[46:40];     // byte 5
                        sq_rd.data.dest <= args[51:48];    // byte 6

                        sq_rd_valid <= 1;
                        state <= STATE_REQ_DONE;
                    end
                STATE_REQ_DONE: begin
                        // wait for the request to be transferred
                        if (sq_rd_valid && sq_rd.ready) begin
                            // clear request and transition to next state
                            sq_rd_valid <= 0;
                            sq_rd.data <= 0;
                            state <= STATE_COPY;
                        end
                    end
                STATE_COPY: begin
                        // wait for a tlast signal
                        // only one should happen since there is only one request
                        if (axis_host_recv[0].tlast || axis_host_recv[1].tlast) begin
                            state <= STATE_IDLE;
                        end
                    end
                default:
                    $display("This should never happen!");
            endcase
            // axi_ctrl write communication (ignored when not in STATE_IDLE)
            // This needs to be handled at all times, or the system will lock up
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

    // handle reading from ctrl registers
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // reset control registers and state
            ctrl_arready <= 0;
            ctrl_rvalid <= 0;
            ctrl_rresp <= 0;
            ctrl_rdata <= 0;
        end else begin
            // handle axi_ctrl reads
            if (ctrl_arready && axi_ctrl.arvalid && ctrl_rvalid && axi_ctrl.rready) begin
                case (axi_ctrl_araddr)
                    REG_ARGS: begin
                        ctrl_rdata[55:0] <= args[55:0];
                        ctrl_rdata[63:56] <= state; // additionally add the state register here
                    end
                    REG_VADDR: begin
                        ctrl_rdata <= vaddr;
                    end
                    REG_LEN: begin
                        ctrl_rdata <= len;
                    end
                    default:
                        $display("This shouldn't happen");
                endcase
                // always acknowledge
                ctrl_rvalid <= 1;
                ctrl_rresp <= 0;
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
        end
    end


endmodule
