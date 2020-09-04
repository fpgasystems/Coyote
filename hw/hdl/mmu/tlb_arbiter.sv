import lynxTypes::*;

/**
 *	TLB request arbiter - Round Robin
 */ 
module tlb_arbiter #(
    parameter integer                   ARB_DATA_BITS = AXI_DATA_BITS
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIntf.s                           req_snk [N_REGIONS],
    dmaIntf.m                           req_src,

    // Multiplexing
    muxUserIntf.s                       mux_user
);

localparam integer BEAT_LOG_BITS = $clog2(ARB_DATA_BITS/8);

logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
dma_req_t [N_REGIONS-1:0] request_snk;
logic [N_REGIONS-1:0] done_snk;
logic [N_REGIONS-1:0] done_snk_r;

logic ready_src;
logic valid_src;
dma_req_t request_src;
logic done_src;

logic [N_REGIONS_BITS-1:0] rr_reg;
logic [N_REGIONS_BITS-1:0] id;

metaIntf #(.DATA_BITS(N_REGIONS_BITS+LEN_BITS-BEAT_LOG_BITS)) user_seq_in ();
metaIntf #(.DATA_BITS(N_REGIONS_BITS)) done_seq_in ();

logic [N_REGIONS_BITS-1:0] done_seq_out_data;

logic [LEN_BITS-BEAT_LOG_BITS-1:0] n_tr;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = req_snk[i].valid;
    assign req_snk[i].ready = ready_snk[i];
    assign request_snk[i] = req_snk[i].req;    
    assign req_snk[i].done = done_snk_r[i];
end

assign req_src.valid = valid_src;
assign ready_src = req_src.ready;
assign req_src.req = request_src;
assign done_src = req_src.done;

// --------------------------------------------------------------------------------
// RR
// --------------------------------------------------------------------------------
always_ff @(posedge aclk or negedge aresetn) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
        done_snk_r <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_REGIONS-1)
                rr_reg <= 0;
        end

        done_snk_r <= done_snk;
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    id = 0;

    done_snk = 0;

    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                valid_src = valid_snk[i+rr_reg-N_REGIONS] && user_seq_in.ready && done_seq_in.ready;
                id = i+rr_reg-N_REGIONS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && user_seq_in.ready && done_seq_in.ready;
                id = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[id] = ready_src && user_seq_in.ready && done_seq_in.ready;
    request_src = request_snk[id];

    done_snk[done_seq_out_data] = done_src;
end

assign n_tr = (request_snk[id].len - 1) >> BEAT_LOG_BITS;
assign user_seq_in.valid = valid_src & ready_src;
assign user_seq_in.data = {id, n_tr};

assign done_seq_in.valid = valid_src & ready_src & request_src.ctl;
assign done_seq_in.data = id;

// Multiplexer sequence
queue #(
    .QTYPE(logic [N_REGIONS_BITS+LEN_BITS-BEAT_LOG_BITS-1:0])
) inst_seq_que_user (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(user_seq_in.valid),
    .rdy_snk(user_seq_in.ready),
    .data_snk(user_seq_in.data),
    .val_src(mux_user.valid),
    .rdy_src(mux_user.ready),
    .data_src({mux_user.id, mux_user.len})
);

// Completion sequence
queue #(
    .QTYPE(logic [N_REGIONS_BITS-1:0])
) inst_seq_que_done (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(done_seq_in.valid),
    .rdy_snk(done_seq_in.ready),
    .data_snk(done_seq_in.data),
    .val_src(done_src),
    .rdy_src(),
    .data_src(done_seq_out_data)
);

/*
ila_arbiter inst_ila_arbiter (
    .clk(aclk),
    .probe0(ready_snk[0]),
    .probe1(ready_snk[1]),
    .probe2(ready_snk[2]),
    .probe3(valid_snk[0]),
    .probe4(valid_snk[1]),
    .probe5(valid_snk[2]),
    .probe6(done_snk[0]),
    .probe7(done_snk[1]),
    .probe8(done_snk[2]),
    .probe9(ready_src),
    .probe10(valid_src),
    .probe11(done_src),
    .probe12(rr_reg),
    .probe13(id),
    .probe14(user_seq_in.valid),
    .probe15(user_seq_in.ready),
    .probe16(user_seq_in.data),
    .probe17(done_seq_in.ready),
    .probe18(done_seq_in.valid),
    .probe19(done_seq_in.data),
    .probe20(mux_user.ready),
    .probe21(mux_user.valid),
    .probe22(mux_user.id),
    .probe23(mux_user.len),
    .probe24(done_seq_out_data)
);
*/

endmodule