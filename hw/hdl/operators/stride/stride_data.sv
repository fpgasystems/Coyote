import lynxTypes::*;

module stride_data #(
    parameter integer   STR_DATA_BITS = AXI_DATA_BITS  
) (
    input  logic        aclk,
    input  logic        aresetn,

    // RDMA
    AXI4S.s             axis_sink,
    AXI4S.m             axis_src,

    // Sequence
    metaIntf.s          params
);

localparam integer BEAT_LOG_BYTES = STR_DATA_BITS/8;
localparam integer BEAT_LOG_BITS = $clog2(BEAT_LOG_BYTES);
localparam integer WORD_SIZE = 3;

// -- FSM
typedef enum logic[0:0]  {ST_IDLE, ST_READ} state_t;
logic [0:0] state_C, state_N;

logic [31:0] cnt_C, cnt_N;
logic [31:0] dwidth_C, dwidth_N;

logic [2*STR_DATA_BITS-1:0] data_C, data_N;
logic [2*STR_DATA_BITS/8-1:0] keep_C, keep_N;
logic last_C, last_N;
logic val_C, val_N;
logic [31:0] dwidth_r_C, dwidth_r_N;
logic [9:0] pntr_out_C = 0, pntr_out_N;
logic [9:0] pntr_in_C = 0, pntr_in_N;

logic [31:0] params_ntr;
logic [31:0] params_dwidth;

// -- REG
always_ff @(posedge aclk, negedge aresetn) begin: PROC_REG
if (aresetn == 1'b0) begin
    state_C <= ST_IDLE;
    val_C <= 1'b0;
    pntr_out_C <= 0;
    pntr_in_C <= 0;
end
else
    state_C <= state_N;
    cnt_C <= cnt_N;
    dwidth_C <= dwidth_N;
    dwidth_r_C <= dwidth_r_N;
    pntr_out_C <= pntr_out_N;
    pntr_in_C <= pntr_in_N;

    val_C <= val_N;
    last_C <= last_N;
    data_C <= data_N;
    keep_C <= keep_N;
end

// -- NSL
always_comb begin: NSL
	state_N = state_C;

	case(state_C)
		ST_IDLE: 
			state_N = (params.ready) ? ST_READ : ST_IDLE;

        ST_READ:
            state_N = ((cnt_C == 0) && (axis_sink.tready & axis_sink.tvalid)) ? ST_IDLE : ST_READ;

	endcase // state_C
end

// -- DP
always_comb begin: DP
    cnt_N = cnt_C;
    dwidth_N = dwidth_C;
    dwidth_r_N = dwidth_r_C;
    pntr_out_N = pntr_out_C;
    pntr_in_N = pntr_in_C;

    val_N = 1'b0;
    last_N = last_C;
    data_N = data_C;
    keep_N = keep_C;

    // Params
    params.ready = 1'b0;

    params_ntr = params.data[0+:32];
    params_dwidth = params.data[32+:32];

    // Data in
    axis_sink.tready = 1'b0;

    // Data out
    axis_src.tvalid = 1'b0; 
    axis_src.tdata = data_C;
    axis_src.tkeep = keep_C;
    axis_src.tlast = last_C;

    case(state_C) 
        ST_IDLE: begin
            if(params.valid) begin
                params.ready = 1'b1;

                cnt_N = params_ntr - 1;
                dwidth_N = params_dwidth;
            end
        end

        ST_READ: begin
            axis_sink.tready = axis_src.tready;

            if(axis_src.tready) begin
                // input
                if(axis_sink.tready & axis_sink.tvalid) begin
                    val_N = 1'b1;
                    last_N = axis_sink.tlast;
                    
                    /*if(dwidth_C > BEAT_LOG_BITS)
                        data_N = axis_sink.tdata;
                    else
                        data_N = {axis_sink.tdata, data_C} >> ((1 << dwidth_C) << WORD_SIZE);*/
                    data_N[((pntr_in_C<<dwidth_C)<<WORD_SIZE)+:STR_DATA_BITS] = axis_sink.tdata;
                    keep_N[(pntr_in_C<<dwidth_C)+:STR_DATA_BITS/8] = axis_sink.tkeep; 
                        
                    if(axis_sink.tlast || (dwidth_C >= BEAT_LOG_BITS)) begin
                        pntr_in_N = 0;
                    end
                    else begin
                        pntr_in_N = ((pntr_in_C + 1) << dwidth_C) == BEAT_LOG_BYTES ? 0 : pntr_in_C + 1;
                    end

                    cnt_N = cnt_C - 1;
                    dwidth_r_N = dwidth_C;
                end
            end
            else begin
                val_N = val_C;
            end
        end

    endcase // state_C

    // output
    if(val_C) begin
        if(last_C || (dwidth_r_C >= BEAT_LOG_BITS)) begin
            pntr_out_N = 0;
            axis_src.tvalid = 1'b1;
        end
        else begin
            pntr_out_N = ((pntr_out_C + 1) << dwidth_r_C) == BEAT_LOG_BYTES ? 0 : pntr_out_C + 1;
            axis_src.tvalid = ((pntr_out_C + 1) << dwidth_r_C) == BEAT_LOG_BYTES;          
        end
    end

end

ila_stride_data inst_str_data (
    .clk(aclk),
    .probe0(state_C),
    .probe1(cnt_C),
    .probe2(dwidth_C),
    .probe3(dwidth_r_C),
    .probe4(pntr_in_C),
    .probe5(pntr_out_C),
    .probe6(last_C),
    .probe7(val_C),
    .probe8(params.valid),
    .probe9(axis_sink.tvalid),
    .probe10(axis_sink.tready),
    .probe11(axis_sink.tlast),
    .probe12(axis_src.tvalid),
    .probe13(axis_src.tready),
    .probe14(axis_src.tlast),
    .probe15(axis_src.tdata),
    .probe16(axis_src.tkeep)
);

endmodule