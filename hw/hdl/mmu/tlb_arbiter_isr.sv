import lynxTypes::*;

/**
 *	TLB request arbiter - Round Robin
 */ 
module tlb_arbiter_isr #(
    parameter integer RDWR = 0
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIsrIntf.s                        req_snk [N_REGIONS],
    dmaIntf.m                           req_src_host,
    dmaIntf.m                           req_src_card
);

logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
dma_isr_req_t [N_REGIONS-1:0] request_snk;
logic [N_REGIONS-1:0] done_snk;
logic [N_REGIONS-1:0] done_snk_r;
logic [N_REGIONS-1:0] isr_return_snk;

logic ready_src;
logic valid_src;
dma_isr_req_t request_src;
logic done_src;

logic [N_REGIONS_BITS-1:0] rr_reg;
logic [N_REGIONS_BITS-1:0] id;

metaIntf #(.DATA_BITS(N_REGIONS_BITS)) done_seq_in ();

logic [N_REGIONS_BITS-1:0] done_seq_out_data;

// --------------------------------------------------------------------------------
// IO
// --------------------------------------------------------------------------------
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = req_snk[i].valid;
    assign req_snk[i].ready = ready_snk[i];
    assign request_snk[i] = req_snk[i].req;    
    assign req_snk[i].done = done_snk_r[i];
    assign req_snk[i].isr_return = 1'b0;
end

assign req_src_host.valid = ready_src & valid_src;
assign req_src_card.valid = ready_src & valid_src;
assign req_src_host.req.paddr = request_src.paddr_host;
assign req_src_card.req.paddr = request_src.paddr_card;
assign req_src_host.req.len = request_src.len;
assign req_src_card.req.len = request_src.len;
assign req_src_host.req.ctl = request_src.ctl;
assign req_src_card.req.ctl = request_src.ctl;
assign req_src_host.req.rsrvd = 0;
assign req_src_card.req.rsrvd = 0;

assign ready_src = req_src_host.ready & req_src_card.ready;
if(RDWR == 0)
    assign done_src = req_src_card.done;
else
    assign done_src = req_src_host.done;

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
                valid_src = valid_snk[i+rr_reg-N_REGIONS] && done_seq_in.ready;
                id = i+rr_reg-N_REGIONS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg] && done_seq_in.ready;
                id = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[id] = ready_src && done_seq_in.ready;
    request_src = request_snk[id];

    done_snk[done_seq_out_data] = done_src;
end

assign done_seq_in.valid = valid_src & ready_src & request_src.ctl;
assign done_seq_in.data = id;

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

endmodule