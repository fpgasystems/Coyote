import lynxTypes::*;

/**
 * Single region requests credits
 */
module tlb_credits_wr #(
    parameter integer ID_REG = 0,
    parameter integer CRED_DATA_BITS = AXI_DATA_BITS
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    // Requests
    dmaIntf.s               req_in,
    dmaIntf.m               req_out,

    // Data write
    input  logic            wxfer
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(CRED_DATA_BITS/8);

logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;

logic [LEN_BITS-BEAT_LOG_BITS:0] n_beats;

// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	cnt_C <= 0;
end
else
    cnt_C <= cnt_N;
end

// -- DP
always_comb begin
    cnt_N =  cnt_C;

    // IO
    req_in.ready = 1'b0;
    req_in.done = req_out.done;
    
    req_out.valid = 1'b0;
    req_out.req.paddr = req_in.req.paddr;
    req_out.req.len = req_in.req.len;
    req_out.req.ctl = req_in.req.ctl;
    req_out.req.rsrvd = 0;

    n_beats = (req_in.req.len - 1) >> BEAT_LOG_BITS;

    if(req_in.valid && req_out.ready && (cnt_C >= n_beats)) begin
        req_in.ready = 1'b1;
        req_out.valid = 1'b1;
 
        cnt_N = wxfer ? cnt_C - (n_beats - 1) : cnt_C - n_beats;
    end
    else begin
        cnt_N = wxfer ? cnt_C + 1 : cnt_C;
    end

end

/*
// DEBUG
if(ID_REG == 0) begin
logic [15:0] cnt_req_in;
logic [15:0] cnt_req_out;

ila_wr_cred inst_ila_wr_cred (
    .clk(aclk),
    .probe0(req_in.valid),
    .probe1(req_in.ready),
    .probe2(req_in.req.len),
    .probe3(req_out.valid),
    .probe4(req_out.ready),    
    .probe5(n_beats),
    .probe6(cnt_C),
    .probe7(wxfer),
    .probe8(cnt_req_in),
    .probe9(cnt_req_out)
);

always_ff @(posedge aclk or negedge aresetn) begin
	if(aresetn == 1'b0) begin
		cnt_req_in <= 0;
		cnt_req_out <= 0;
	end 
	else begin
	   cnt_req_in <= (req_in.valid & req_in.ready) ? cnt_req_in + 1 : cnt_req_in;
	   cnt_req_out <= (req_out.valid & req_out.ready) ? cnt_req_out + 1 : cnt_req_out;	
	end
end
end
*/


endmodule