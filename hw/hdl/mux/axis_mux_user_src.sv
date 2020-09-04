import lynxTypes::*;

module axis_mux_user_src #(
    parameter integer MUX_DATA_BITS = AXI_DATA_BITS
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    muxUserIntf.m                           mux,

    AXI4S.s                                 axis_in,
    AXI4S.m                                 axis_out [N_REGIONS]
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
// -- Mux 
// ----------------------------------------------------------------------------------------------------------------------- 
// -- interface loop issues => temp signals
logic                                   axis_in_tvalid;
logic                                   axis_in_tready;
logic [MUX_DATA_BITS-1:0]               axis_in_tdata;
logic [MUX_DATA_BITS/8-1:0]             axis_in_tkeep;
logic                                   axis_in_tlast;

logic [N_ID-1:0]                        axis_out_tvalid;
logic [N_ID-1:0]                        axis_out_tready;
logic [N_ID-1:0][MUX_DATA_BITS-1:0]     axis_out_tdata;
logic [N_ID-1:0][MUX_DATA_BITS/8-1:0]   axis_out_tkeep;
logic [N_ID-1:0]                        axis_out_tlast;

assign axis_in_tvalid = axis_in.tvalid;
assign axis_in_tdata = axis_in.tdata;
assign axis_in_tkeep = axis_in.tkeep;
assign axis_in_tlast = axis_in.tlast;
assign axis_in.tready = axis_in_tready;

for(genvar i = 0; i < N_ID; i++) begin
    assign axis_out[i].tvalid = axis_out_tvalid[i];
    assign axis_out[i].tdata = axis_out_tdata[i];
    assign axis_out[i].tkeep = axis_out_tkeep[i];
    assign axis_out[i].tlast = axis_out_tlast[i];
    assign axis_out_tready[i] = axis_out[i].tready;
end

// -- Mux
always_comb begin
    for(int i = 0; i < N_ID; i++) begin
        axis_out_tdata[i] = axis_in_tdata;
        axis_out_tkeep[i] = axis_in_tkeep;
        axis_out_tlast[i] = axis_in_tlast;
        if(state_C == ST_MUX) begin
            axis_out_tvalid[i] = (id_C == i) ? axis_in_tvalid : 1'b0;
        end
        else begin
            axis_out_tvalid[i] = 1'b0;
        end
    end

    if(id_C < N_ID && state_C == ST_MUX) 
        axis_in_tready = axis_out_tready[id_C];
    else 
        axis_in_tready = 1'b0;
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
  tr_done = (cnt_C == n_beats_C) && (axis_in_tvalid & axis_in_tready);

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
        cnt_N = (axis_in_tvalid & axis_in_tready) ? cnt_C + 1 : cnt_C;
      end
    end

  endcase
end

endmodule