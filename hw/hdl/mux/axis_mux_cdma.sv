import lynxTypes::*;

/**
 * CDMA multiplexer
 *
 * DMA request adjustments when multiple channels are enabled.
 */
module axis_mux_cdma (
    input  logic                            aclk,
    input  logic                            aresetn,

    dmaIntf.s                               CDMA,                   // Regular
    dmaIntf.m                               CDMA_adj [N_DDR_CHAN]   // Adjusted
);

localparam integer N_DDR_CHAN_BITS = $clog2(N_DDR_CHAN);

logic [N_DDR_CHAN-1:0] cdma_ready_adj;
logic [N_DDR_CHAN-1:0] cdma_done_adj;

logic [N_DDR_CHAN-1:0][15:0] cdma_done_cnt;
logic cdma_done;

for(genvar i = 0; i < N_DDR_CHAN; i++) begin
        if(N_DDR_CHAN > 1) begin
            assign CDMA_adj[i].req.paddr = {{N_DDR_CHAN_BITS{1'b0}}, CDMA.req.paddr[N_DDR_CHAN_BITS+:PADDR_BITS-N_DDR_CHAN_BITS]};
		    assign CDMA_adj[i].req.len = {{N_DDR_CHAN_BITS{1'b0}}, CDMA.req.len[N_DDR_CHAN_BITS+:LEN_BITS-N_DDR_CHAN_BITS]};
        end
        else begin
            assign CDMA_adj[i].req.paddr = CDMA.req.paddr;
		    assign CDMA_adj[i].req.len = CDMA.req.len;
        end
        
        assign CDMA_adj[i].req.ctl = CDMA.req.ctl;
		assign CDMA_adj[i].req.rsrvd = 0;
		assign CDMA_adj[i].valid = CDMA.valid & CDMA.ready;

        assign cdma_ready_adj[i] = CDMA_adj[i].ready;
        assign cdma_done_adj[i] = CDMA_adj[i].done;
end

// Ready
assign CDMA.ready = &cdma_ready_adj;

// Done signal
always_comb begin
    cdma_done = 1'b1;
    
    for(int i = 0; i < N_DDR_CHAN; i++) begin
        if(cdma_done_cnt[i] == 0) cdma_done = 1'b0; 
    end 
end

// Done counters
always_ff @(posedge aclk, negedge aresetn) begin
    if(~aresetn) begin
        cdma_done_cnt <= 0;
    end
    else begin
        for(int i = 0; i < N_DDR_CHAN; i++) begin
            // Counter
            if(cdma_done) begin
                cdma_done_cnt[i] <= cdma_done_adj[i] ? cdma_done_cnt[i] : cdma_done_cnt[i] - 1;
            end
            else begin
                cdma_done_cnt[i] <= cdma_done_adj[i] ? cdma_done_cnt[i] + 1 : cdma_done_cnt[i];
            end
        end
    end
end

assign CDMA.done = cdma_done;
/*
ila_mux_cdma inst_ila_cdma (
    .clk(aclk),
    .probe0(CDMA.valid),
    .probe1(CDMA.ready),
    .probe2(CDMA.req.paddr),
    .probe3(CDMA.req.len),
    .probe4(CDMA.req.ctl),
    .probe5(CDMA_adj[0].valid),
    .probe6(CDMA_adj[0].ready),
    .probe7(CDMA_adj[1].valid),
    .probe8(CDMA_adj[1].ready),
    .probe9(CDMA_adj[0].req.paddr),
    .probe10(CDMA_adj[0].req.len),
    .probe11(CDMA_adj[1].req.paddr),
    .probe12(CDMA_adj[1].req.len),
    .probe13(CDMA.done),
    .probe14(CDMA_adj[0].done),
    .probe15(CDMA_adj[1].done)
);
*/
endmodule