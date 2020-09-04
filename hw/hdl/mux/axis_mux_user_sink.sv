import lynxTypes::*;

/**
 * User multiplexer 
 */
module axis_mux_user_sink #(
    parameter integer MUX_DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxUserIntf.m                           mux,

    AXI4S.s                                 axis_in [N_REGIONS],
    AXI4S.m                                 axis_out
);

// -- Constants
localparam integer BEAT_LOG_BITS = $clog2(MUX_DATA_BITS/8);
localparam integer N_ID = N_REGIONS;
localparam integer N_ID_BITS = N_REGIONS_BITS;

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_MUX} state_t;
logic [0:0] state_C, state_N;

// -- Internal regs
logic [N_ID_BITS-1:0] id_C, id_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] cnt_C, cnt_N;
logic [LEN_BITS-BEAT_LOG_BITS:0] n_beats_C, n_beats_N;

// -- Internal signals
logic tr_done; 

// ----------------------------------------------------------------------------------------------------------------------- 
// Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic [N_ID-1:0]                            axis_in_tvalid;
logic [N_ID-1:0]                            axis_in_tready;
logic [N_ID-1:0][MUX_DATA_BITS-1:0]         axis_in_tdata;
logic [N_ID-1:0][MUX_DATA_BITS/8-1:0]       axis_in_tkeep;
logic [N_ID-1:0]                            axis_in_tlast;

logic                                       axis_out_tvalid;
logic                                       axis_out_tready;
logic [MUX_DATA_BITS-1:0]                   axis_out_tdata;
logic [MUX_DATA_BITS/8-1:0]                 axis_out_tkeep;
logic                                       axis_out_tlast;

for(genvar i = 0; i < N_ID; i++) begin
    assign axis_in_tvalid[i] = axis_in[i].tvalid;
    assign axis_in_tdata[i] = axis_in[i].tdata;
    assign axis_in_tkeep[i] = axis_in[i].tkeep;
    assign axis_in_tlast[i] = axis_in[i].tlast;
    assign axis_in[i].tready = axis_in_tready[i];
end

assign axis_out.tvalid = axis_out_tvalid;
assign axis_out.tdata = axis_out_tdata;
assign axis_out.tkeep = axis_out_tkeep;
assign axis_out.tlast = axis_out_tlast;
assign axis_out_tready = axis_out.tready;

// -- Mux
always_comb begin
    for(int i = 0; i < N_ID; i++) begin
        if(state_C == ST_MUX)
          axis_in_tready[i] = (id_C == i) ? axis_out_tready : 1'b0;      
        else 
          axis_in_tready[i] = 1'b0;
    end

    if(id_C < N_ID && state_C == ST_MUX) begin
        axis_out_tdata = axis_in_tdata[id_C];
        axis_out_tkeep = axis_in_tkeep[id_C];
        axis_out_tlast = axis_in_tlast[id_C];
        axis_out_tvalid = axis_in_tvalid[id_C];
    end
    else begin
        axis_out_tdata = 0;
        axis_out_tkeep = 0;
        axis_out_tlast = 1'b0;
        axis_out_tvalid = 1'b0;
    end
end

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Memory subsystem 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
	state_C <= ST_IDLE;
end
else
  state_C <= state_N;

  cnt_C <= cnt_N;
  id_C <= id_N;
  n_beats_C <= n_beats_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = mux.ready ? ST_MUX : ST_IDLE;

    ST_MUX:
      state_N = tr_done ? (mux.ready ? ST_MUX : ST_IDLE) : ST_MUX;

	endcase // state_C
end

// -- DP
always_comb begin : DP
  cnt_N = cnt_C;
  id_N = id_C;
  n_beats_N = n_beats_C;

  // Transfer done
  tr_done = (cnt_C == n_beats_C) && (axis_out_tvalid & axis_out_tready);

  // Memory subsystem
  mux.valid = 1'b0;

  case(state_C)
    ST_IDLE: begin
      cnt_N = 0;
      if(mux.ready) begin
        mux.valid = 1'b1;
        id_N = mux.id;
        n_beats_N = mux.len;   
      end   
    end

    ST_MUX: begin
      if(tr_done) begin
        cnt_N = 0;
        if(mux.ready) begin
          mux.valid = 1'b1;
          id_N = mux.id;
          n_beats_N = mux.len;    
        end
      end 
      else begin
        cnt_N = (axis_out_tvalid & axis_out_tready) ? cnt_C + 1 : cnt_C;
      end
    end

  endcase
end
/*
ila_2 inst_ila_2 (
  .clk(aclk),
  .probe0(mux.ready),
  .probe1(mux.valid),
  .probe2(mux.len),
  .probe3(mux.id),
  .probe4(cnt_C),
  .probe5(state_C),
  .probe6(n_beats_C),
  .probe7(id_C),
  .probe8(tr_done),
  .probe9(axis_out_tvalid),
  .probe10(axis_out_tready)
);
*/

endmodule