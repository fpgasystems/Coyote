
import lynxTypes::*;

`include "axi_macros.svh"
`include "lynx_macros.svh"

module request_splitter
(
    input logic aclk,
    input logic aresetn,
    input logic [31:0] max_len_mask,

    metaIntf.s req_in,
    //input logic [47:0] req_vaddr,
    //input logic [27:0] req_len,
    //input logic [3:0] req_dest,
    //input logic req_valid,
    //output logic req_ready,

    metaIntf.m req_out
    //output logic [47:0] out_vaddr,
    //output logic [27:0] out_len,
    //output logic [3:0] out_dest,
    //output logic out_valid,
    //input logic out_ready
);

/*
    ila_meta_req inst_ila_req_in (
        .probe0(req_in.data.opcode),
        .probe1(req_in.data.strm),
        .probe2(req_in.data.mode),
        .probe3(req_in.data.rdma),
        .probe4(req_in.data.remote),
        .probe5(req_in.data.vfid),
        .probe6(req_in.data.pid),
        .probe7(req_in.data.dest),
        .probe8(req_in.data.last),
        .probe9(req_in.data.vaddr),
        .probe10(req_in.data.len),
        .probe11(req_in.data.actv),
        .probe12(req_in.data.host),
        .probe13(req_in.data.offs),
        .probe14(req_in.valid),
        .probe15(req_in.ready),
        .clk(aclk)
    );

    ila_meta_req inst_ila_req_out (
        .probe0(req_out.data.opcode),
        .probe1(req_out.data.strm),
        .probe2(req_out.data.mode),
        .probe3(req_out.data.rdma),
        .probe4(req_out.data.remote),
        .probe5(req_out.data.vfid),
        .probe6(req_out.data.pid),
        .probe7(req_out.data.dest),
        .probe8(req_out.data.last),
        .probe9(req_out.data.vaddr),
        .probe10(req_out.data.len),
        .probe11(req_out.data.actv),
        .probe12(req_out.data.host),
        .probe13(req_out.data.offs),
        .probe14(req_out.valid),
        .probe15(req_out.ready),
        .clk(aclk)
    );
    //*/

    // signals
    logic [31:0] max_len;
    always_comb max_len = max_len_mask + 1;

    // latching registers
    req_t out_data;
    logic [47:0] base_addr;
    logic [63:0] remaining_length;

    // states
    localparam logic [3:0] StateIdle = 0;
    localparam logic [3:0] StateRequest = 1;
    localparam logic [3:0] StateWait = 2;

    // state registers
    logic [3:0] state;
    wreq_t in_data;

    // assignments
    assign in_data = req_in.data;
    assign req_in.ready = (state == StateIdle) & aresetn; // state is idle and module is not in reset
    assign req_out.data = out_data;

    // state machine
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // reset outputs
            req_out.valid <= 0;
            // reset state register
            state <= 0;
            // reset latching registers
            out_data <= 0;
            remaining_length <= 0;
            base_addr <= 0;
        end
        else begin
            case (state)
                StateIdle:
                    begin
                        // if data is available, latch and progress to next state
                        if (req_in.valid) begin
                            // latch the parameters
                            out_data.opcode <= in_data.opcode;
                            out_data.strm <= in_data.strm;
                            out_data.mode <= in_data.mode;
                            out_data.rdma <= in_data.rdma;
                            out_data.remote <= in_data.remote;
                            out_data.vfid <= in_data.vfid;
                            out_data.pid <= in_data.pid;
                            out_data.dest <= in_data.dest;
                            out_data.actv <= in_data.actv;
                            out_data.host <= in_data.host;
                            out_data.offs <= in_data.offs;
                            out_data.last <= in_data.last;

                            remaining_length <= in_data.len;
                            base_addr <= in_data.vaddr;
                            // update state register
                            state <= StateRequest;
                        end
                    end
                StateRequest:
                    begin
                        // will there be another request
                        if (remaining_length > max_len) begin
                            // write output
                            out_data.vaddr <= base_addr;
                            out_data.len <= max_len;
                            req_out.valid <= 1;
                            // update latching registers
                            base_addr <= base_addr + max_len;
                            remaining_length <= remaining_length - max_len;
                            // state transition
                            state <= StateWait;
                        end
                        else begin
                            // write output
                            out_data.vaddr <= base_addr;
                            out_data.len <= remaining_length;
                            req_out.valid <= 1;
                            // update latching registers
                            base_addr <= base_addr + remaining_length;
                            remaining_length <= 0; // as remaining_length was less than max_len
                            // state transition
                            state <= StateWait;
                        end
                    end
                StateWait:
                    begin
                        // wait until out_ready
                        if (req_out.ready) begin
                            // no longer valid
                            req_out.valid <= 0;
                            // check if more transfers follow
                            if (remaining_length != 0) begin
                                // more transfers follow, so back to StateRequest
                                state <= StateRequest;
                            end
                            else begin
                                // no more transfers, so back to StateIdle
                                state <= StateIdle;
                            end
                        end
                    end
                default:
                    $display("This should never happen.");
            endcase
        end
    end


endmodule
