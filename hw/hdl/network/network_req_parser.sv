import lynxTypes::*;

/**
 * Network request parser
 *
 * Parses the incoming RDMA requests. 
 * Requests:
 *  - Op code [4:0]         - Based on the mode it carries one of the op codes
 *  - QP number [28:5]      - Local QP number
 *  - Region ID [32:29]     - Region ID, hardcoded
 *  - Host access [33]      - Access is forwarded to the host or to user logic, hardcoded
 *  - Mode [34]             - Parse the requests, or use raw opcodes. Raw codes are used for special operations, e.g. when final data length is unknown
 *  - Vaddr loc. [111:64]   - Local buffer virtual address
 *  - Vaddr rem. [159:112]  - Remote vuffer virtual address
 *  - Size [191:160]        - Size of the transfer
 *  - Parameters [255:192]  - Optional Farview parameters
 *
 */
module network_req_parser #(
    parameter integer       ID_REG = 0,
    parameter integer       HOST = 0
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    metaIntf.s              req_in,
    metaIntf.m              req_out,

    output logic [31:0]     used
);

// Opcodes
localparam integer APP_READ = 0;
localparam integer APP_WRITE = 1;
localparam integer APP_RPC = 2;

localparam integer RC_RDMA_WRITE_FIRST = 5'h6;
localparam integer RC_RDMA_WRITE_MIDDLE = 5'h7;
localparam integer RC_RDMA_WRITE_LAST = 5'h8;
localparam integer RC_RDMA_WRITE_LAST_WITH_IMD = 5'h9;
localparam integer RC_RDMA_WRITE_ONLY = 5'hA;
localparam integer RC_RDMA_WRITE_ONLY_WIT_IMD = 5'hB;
localparam integer RC_RDMA_READ_REQUEST = 5'hC;
localparam integer RC_RDMA_READ_RESP_FIRST = 5'hD;
localparam integer RC_RDMA_READ_RESP_MIDDLE = 5'hE;
localparam integer RC_RDMA_READ_RESP_LAST = 5'hF;
localparam integer RC_RDMA_READ_RESP_ONLY = 5'h10;
localparam integer RC_ACK = 5'h11;
localparam integer RC_RDMA_RPC_REQUEST = 5'h18;

// -- FSM
typedef enum logic[2:0]  {ST_IDLE, ST_PARSE_READ, ST_PARSE_WRITE_INIT, ST_PARSE_WRITE, ST_PARSE_RPC, ST_SEND_READ, ST_SEND_WRITE, ST_SEND_BASE} state_t;
logic [2:0] state_C, state_N;

// TODO: Needs interfaces, cleaning necessary

// Cmd 64
logic [4:0] op_C, op_N;
logic [23:0] qp_C, qp_N;
logic [3:0] lreg_C, lreg_N;
logic [0:0] host_C, host_N;
logic [29:0] rsrvd_C, rsrvd_N;
// Params 192
logic [47:0] lvaddr_C, lvaddr_N;
logic [47:0] rvaddr_C, rvaddr_N;
logic [31:0] len_C, len_N;
logic [63:0] params_C, params_N;

// Send
logic [4:0] pop_C, pop_N;
logic [31:0] plen_C, plen_N;
logic [47:0] plvaddr_C, plvaddr_N;
logic [47:0] prvaddr_C, prvaddr_N;

// Requests internal
metaIntf #(.DATA_BITS(FV_REQ_BITS)) req_pre_parsed ();
metaIntf #(.DATA_BITS(FV_REQ_BITS)) req_parsed ();

// Decoupling
axis_data_fifo_cnfg_rdma_256 inst_cmd_queue_in (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(req_in.valid),
  .s_axis_tready(req_in.ready),
  .s_axis_tdata(req_in.data),
  .m_axis_tvalid(req_pre_parsed.valid),
  .m_axis_tready(req_pre_parsed.ready),
  .m_axis_tdata(req_pre_parsed.data),
  .axis_wr_data_count(used)
);

logic [31:0] queue_used_out;

axis_data_fifo_cnfg_rdma_256 inst_cmd_queue_out (
  .s_axis_aresetn(aresetn),
  .s_axis_aclk(aclk),
  .s_axis_tvalid(req_parsed.valid),
  .s_axis_tready(req_parsed.ready),
  .s_axis_tdata(req_parsed.data),
  .m_axis_tvalid(req_out.valid),
  .m_axis_tready(req_out.ready),
  .m_axis_tdata(req_out.data),
  .axis_wr_data_count(queue_used_out)
);

// REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
	state_C <= state_N;

    op_C <= op_N;
    qp_C <= qp_N;
    lreg_C <= lreg_N;
    host_C <= host_N;
    rsrvd_C <= rsrvd_N;

    lvaddr_C <= lvaddr_N;
    rvaddr_C <= rvaddr_N;
    len_C <= len_N;
    params_C <= params_N;

    pop_C <= pop_N;
    plen_C <= plen_N;
    plvaddr_C <= plvaddr_N;
    prvaddr_C <= prvaddr_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			if(req_pre_parsed.valid) begin
                if(req_pre_parsed.data[34]) begin
                    state_N = ST_SEND_BASE;
                end
                else begin
                    case(req_pre_parsed.data[4:0])
                        APP_READ:
                            state_N = ST_PARSE_READ;
                        APP_WRITE:
                            state_N = ST_PARSE_WRITE_INIT;
                        APP_RPC:
                            state_N = ST_PARSE_RPC;

                        default: state_N = ST_IDLE;
                    endcase
                end
            end

        ST_PARSE_READ:
            state_N = ST_SEND_READ;
    
        ST_PARSE_WRITE_INIT: 
            state_N = ST_SEND_WRITE;

        ST_PARSE_WRITE:
            state_N = ST_SEND_WRITE;

        ST_PARSE_RPC:
            state_N = ST_SEND_READ;

        ST_SEND_READ:
            if(req_parsed.ready) begin
                state_N = ST_IDLE;
            end

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                state_N = len_C ? ST_PARSE_WRITE : ST_IDLE;
            end

        ST_SEND_BASE:
            if(req_parsed.ready) begin
                state_N = ST_IDLE;
            end

	endcase // state_C
end

// DP
always_comb begin: DP
    op_N = op_C;
    qp_N = qp_C;
    lreg_N = lreg_C;
    host_N = host_C;
    rsrvd_N = rsrvd_C;

    len_N = len_C;
    lvaddr_N = lvaddr_C;
    rvaddr_N = rvaddr_C;
    params_N = params_C;

    pop_N = pop_C;
    plen_N = plen_C;
    plvaddr_N = plvaddr_C;
    prvaddr_N = prvaddr_C;

    // Flow
    req_pre_parsed.ready = 1'b0;
    req_parsed.valid = 1'b0;

    // Data
    req_parsed.data[255:0] = {params_C, plen_C, prvaddr_C, plvaddr_C, rsrvd_C, host_C, lreg_C, qp_C, pop_C};

    case(state_C)
        ST_IDLE: begin
            req_pre_parsed.ready = 1'b1;

            qp_N = req_pre_parsed.data[28:5]; // qp number
            lreg_N = ID_REG;//req_pre_parsed.data[32:29]; // local region
            host_N = HOST;//req_pre_parsed.data[33:33]; // host
            rsrvd_N = 0;//req_pre_parsed.data[63:34]; // reserved
            params_N = req_pre_parsed.data[255:192]; // params

            if(req_pre_parsed.valid) begin
                if(req_pre_parsed.data[34]) begin
                    pop_N = req_pre_parsed.data[4:0]; // op code              
                    plvaddr_N = req_pre_parsed.data[111:64]; // local vaddr
                    prvaddr_N = req_pre_parsed.data[159:112]; // remote vaddr
                    plen_N = req_pre_parsed.data[191:160]; // length 
                    
                end
                else begin
                    op_N = req_pre_parsed.data[4:0]; // op code
                    lvaddr_N = req_pre_parsed.data[111:64]; // local vaddr
                    rvaddr_N = req_pre_parsed.data[159:112]; // remote vaddr
                    len_N = req_pre_parsed.data[191:160]; // length 
                end
            end
        end

        ST_PARSE_READ: begin
            pop_N = RC_RDMA_READ_REQUEST;
            plen_N = len_C;
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
        end

        ST_PARSE_WRITE_INIT: begin
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
            
            if(len_C > PMTU_BITS) begin
                lvaddr_N = lvaddr_C + PMTU_BITS;
                rvaddr_N = rvaddr_C + PMTU_BITS;
                len_N = len_C - PMTU_BITS;

                pop_N = RC_RDMA_WRITE_FIRST;
                plen_N = PMTU_BITS;              
            end
            else begin
                len_N = 0;

                pop_N = RC_RDMA_WRITE_ONLY;
                plen_N = len_C;
            end
        end

        ST_PARSE_WRITE: begin
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
            
            if(len_C > PMTU_BITS) begin
                lvaddr_N = lvaddr_C + PMTU_BITS;
                rvaddr_N = rvaddr_C + PMTU_BITS;
                len_N = len_C - PMTU_BITS;

                pop_N = RC_RDMA_WRITE_MIDDLE;
                plen_N = PMTU_BITS;              
            end
            else begin
                len_N = 0;

                pop_N = RC_RDMA_WRITE_LAST;
                plen_N = len_C;
            end
        end
    
        ST_PARSE_RPC: begin
            pop_N = RC_RDMA_RPC_REQUEST;
            plen_N = len_C;
            plvaddr_N = lvaddr_C;
            prvaddr_N = rvaddr_C;
        end

        ST_SEND_READ: 
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

        ST_SEND_WRITE:
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

        ST_SEND_BASE:
            if(req_parsed.ready) begin
                req_parsed.valid = 1'b1;
            end

    endcase
end
/*
// DEBUG ila --------------------------------------------------------------------------------

logic [31:0] cnt_in, cnt_out;

always_ff @(posedge aclk, negedge aresetn) begin
if (aresetn == 1'b0) begin
	cnt_in <= 0;
    cnt_out <= 0;
end
else
	cnt_in <= (req_pre_parsed.valid & req_pre_parsed.ready) ? cnt_in + 1 : cnt_in;
    cnt_out <= (req_parsed.valid & req_parsed.ready) ? cnt_out + 1 : cnt_out;
end
*/

/*
ila_parser inst_ila_parser (
    .clk(aclk),
    .probe0(state_C),
    .probe1(op_C),
    .probe2(qp_C),
    .probe3(lreg_C),
    .probe4(host_C),
    .probe5(lvaddr_C),
    .probe6(rvaddr_C),
    .probe7(len_C),
    .probe8(pop_C),
    .probe9(plen_C),
    .probe10(plvaddr_C),
    .probe11(prvaddr_C),
    .probe12(req_parsed.valid),
    .probe13(req_parsed.ready),
    .probe14(req_pre_parsed.valid),
    .probe15(req_pre_parsed.ready),
    .probe16(cnt_in),
    .probe17(cnt_out)
);
*/

endmodule