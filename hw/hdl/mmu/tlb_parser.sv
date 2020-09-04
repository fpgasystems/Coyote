import lynxTypes::*;

/**
 * Request parser
 */
module tlb_parser (
    input  logic            aclk,
    input  logic            aresetn,
    
    reqIntf.s               req_in,
    reqIntf.m               req_out
);

localparam integer PARSE_SIZE = PMTU_BITS; // probably best to keep at PMTU size

// -- FSM
typedef enum logic[1:0]  {ST_IDLE, ST_PARSE, ST_SEND} state_t;
logic [1:0] state_C, state_N;

logic [LEN_BITS-1:0] len_C, len_N;
logic [VADDR_BITS-1:0] vaddr_C, vaddr_N;
logic ctl_C, ctl_N;
logic sync_C, sync_N;
logic stream_C, stream_N;
logic [3:0] dest_C, dest_N;

logic [LEN_BITS-1:0] plen_C, plen_N;
logic [VADDR_BITS-1:0] pvaddr_C, pvaddr_N;
logic pctl_C, pctl_N;

// REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
	state_C <= state_N;

    len_C <= len_N;
    vaddr_C <= vaddr_N;
    ctl_C <= ctl_N;
    sync_C <= sync_N;
    stream_C <= stream_N;
    dest_C <= dest_N;

    plen_C <= plen_N;
    pvaddr_C <= pvaddr_N;
    pctl_C <= pctl_N;
end

// NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
            if(req_in.valid) begin
                state_N = ST_PARSE;
            end
            
        ST_PARSE:
            state_N = ST_SEND;

        ST_SEND:
            if(req_out.ready) 
                state_N = len_C ? ST_PARSE : ST_IDLE;

	endcase // state_C
end

// DP
always_comb begin: DP
    len_N = len_C;
    vaddr_N = vaddr_C;
    ctl_N = ctl_C;
    sync_N = sync_C;
    stream_N = stream_C;
    dest_N = dest_C;

    plen_N = plen_C;
    pvaddr_N = pvaddr_C;
    pctl_N = pctl_C;

    // Flow
    req_in.ready = 1'b0;
    req_out.valid = 1'b0;

    // Data
    req_out.req.len = plen_C;
    req_out.req.vaddr = pvaddr_C;
    req_out.req.ctl = pctl_C;
    req_out.req.sync = sync_C;
    req_out.req.stream = stream_C;
    req_out.req.dest = dest_C;
    req_out.req.rsrvd = 0;

    case(state_C)
        ST_IDLE: begin
            req_in.ready = 1'b1;
            if(req_in.valid) begin
                len_N = req_in.req.len;
                vaddr_N = req_in.req.vaddr;
                ctl_N = req_in.req.ctl;
                sync_N = req_in.req.sync;
                stream_N = req_in.req.stream;
                dest_N = req_in.req.dest;
            end
        end

        ST_PARSE: begin
            pvaddr_N = vaddr_N;
            
            if(len_C > PARSE_SIZE) begin
                vaddr_N = vaddr_C + PARSE_SIZE;
                len_N = len_C - PARSE_SIZE;

                plen_N = PARSE_SIZE;
                pctl_N = 1'b0;
            end
            else begin
                len_N = 0;

                plen_N = len_C;
                pctl_N = ctl_C;
            end
        end

        ST_SEND: 
            if(req_out.ready) begin
                req_out.valid = 1'b1;
            end

    endcase
end

endmodule