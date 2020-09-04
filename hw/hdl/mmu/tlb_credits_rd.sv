import lynxTypes::*;

/**
 * Single region requests credits
 */
module tlb_credits_rd #(
    parameter integer ID_REG = 0,
    parameter integer CRED_DATA_BITS = AXI_DATA_BITS
) (
    input  logic            aclk,
    input  logic            aresetn,
    
    // Requests
    dmaIntf.s               req_in,
    dmaIntf.m               req_out,

    // Data read
    input  logic            rxfer,
    output logic [3:0]      rd_dest
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(CRED_DATA_BITS/8);

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_READ} state_t;
logic [0:0] state_C, state_N;

logic [7:0] cred_reg_C, cred_reg_N;
logic [LEN_BITS-BEAT_LOG_BITS-1:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS-1:0] n_beats_C, n_beats_N;
logic [3:0] dest_C, dest_N;

logic req_sent;
logic req_done;

logic [LEN_BITS-BEAT_LOG_BITS-1:0] rd_len;

metaIntf #(.DATA_BITS(4+LEN_BITS-BEAT_LOG_BITS)) req_que_in ();
metaIntf #(.DATA_BITS(4+LEN_BITS-BEAT_LOG_BITS)) req_que_out ();

// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	  cred_reg_C <= N_OUTSTANDING;
    state_C <= ST_IDLE;
end
else
    cred_reg_C <= cred_reg_N;
    state_C <= state_N;
    cnt_C <= cnt_N;
    n_beats_C <= n_beats_N;
    dest_C <= dest_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = req_que_out.valid ? ST_READ : ST_IDLE;

    ST_READ:
        state_N = req_done ? (req_que_out.valid ? ST_READ : ST_IDLE) : ST_READ;

	endcase // state_C
end

// -- DP
always_comb begin
  cred_reg_N = cred_reg_C;
  cnt_N =  cnt_C;
  n_beats_N = n_beats_C;
  dest_N = dest_C;

  // IO
  req_in.ready = 1'b0;
  req_in.done = req_out.done;
  
  req_out.valid = 1'b0;
  req_out.req.paddr = req_in.req.paddr;
  req_out.req.len = req_in.req.len;
  req_out.req.ctl = req_in.req.ctl;
  req_out.req.rsrvd = 0;

  // Status
  req_sent = req_in.valid && req_out.ready && req_que_in.ready && ((cred_reg_C > 0) || req_done);
  req_done = (cnt_C == n_beats_C) && rxfer;

  // Outstanding queue
  req_que_in.valid = 1'b0;
  rd_len = (req_in.req.len - 1) >> BEAT_LOG_BITS;
  req_que_in.data = {req_in.req.dest, rd_len};
  req_que_out.ready = 1'b0;

  if(req_sent && !req_done)
      cred_reg_N = cred_reg_C - 1;
  else if(req_done && !req_sent)
      cred_reg_N = cred_reg_C + 1;

  if(req_in.valid && req_out.ready && req_que_in.ready && ((cred_reg_C > 0) || req_done)) begin
      req_in.ready = 1'b1;
      req_out.valid = 1'b1;
      req_que_in.valid = 1'b1;
  end

  case(state_C)
    ST_IDLE: begin
      cnt_N = 0;
      if(req_que_out.valid) begin
        req_que_out.ready = 1'b1;
        n_beats_N = req_que_out.data[LEN_BITS-BEAT_LOG_BITS-1:0];
        dest_N = req_que_out.data[LEN_BITS-BEAT_LOG_BITS+:4];   
      end   
    end

    ST_READ: begin
      if(req_done) begin
        cnt_N = 0;
        if(req_que_out.valid) begin
            req_que_out.ready = 1'b1;
            n_beats_N = req_que_out.data;
            dest_N = req_que_out.data[LEN_BITS-BEAT_LOG_BITS+:4];
        end
      end 
      else begin
        cnt_N = rxfer ? cnt_C + 1 : cnt_C;
      end
    end

  endcase
end

// Output dest
assign rd_dest = dest_C;

// Outstanding
queue_stream #(.QTYPE(logic [4+LEN_BITS-BEAT_LOG_BITS-1:0])) inst_dque (
  .aclk(aclk),
  .aresetn(aresetn),
  .val_snk(req_que_in.valid),
  .rdy_snk(req_que_in.ready),
  .data_snk(req_que_in.data),
  .val_src(req_que_out.valid),
  .rdy_src(req_que_out.ready),
  .data_src(req_que_out.data)
);

/*
// DEBUG
if(ID_REG == 0) begin
logic [15:0] cnt_req_in;
logic [15:0] cnt_req_out;

ila_rd_cred inst_ila_rd_cred (
    .clk(aclk),
    .probe0(state_C),
    .probe1(req_in.valid),
    .probe2(req_in.ready),
    .probe3(req_in.req.len),
    .probe4(cred_reg_C),
    .probe5(cnt_C),
    .probe6(n_beats_C),
    .probe7(req_sent),
    .probe8(rxfer),
    .probe9(req_sent),
    .probe10(req_done),
    .probe11(cnt_req_in),
    .probe12(cnt_req_out)
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