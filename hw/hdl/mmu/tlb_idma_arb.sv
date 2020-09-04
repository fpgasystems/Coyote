import lynxTypes::*;

/**
 *	TLB idma request arbitration between read and write channels
 */ 
module tlb_idma_arb #(
    parameter integer RDWR = 0
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

    input  logic                        mutex,

    dmaIsrIntf.s                        rd_idma,
    dmaIsrIntf.s                        wr_idma,
    dmaIsrIntf.m                        idma
);

// IDMA
logic sync_seq_snk_ready;
logic sync_seq_snk_valid;
logic [1:0] sync_seq_snk_data; // 1: ISR return, 0: rd/wr
logic [1:0] sync_seq_src_data;

// Sequence queue IDMA
queue #(
    .QTYPE(logic [1:0])
) inst_seq_que_idma (
    .aclk(aclk),
    .aresetn(aresetn),
    .val_snk(sync_seq_snk_valid),
    .rdy_snk(sync_seq_snk_ready),
    .data_snk(sync_seq_snk_data),
    .val_src(idma.done),
    .rdy_src(),
    .data_src(sync_seq_src_data)
);

always_comb begin
    rd_idma.done = idma.done && ~sync_seq_src_data[0];
    wr_idma.done = idma.done && sync_seq_src_data[0];
    
    rd_idma.isr_return = sync_seq_src_data[1];
    wr_idma.isr_return = sync_seq_src_data[1];

    if(mutex) begin // mutex[1]
        wr_idma.ready = idma.ready && sync_seq_snk_ready;
        rd_idma.ready = 1'b0;

        sync_seq_snk_valid = wr_idma.valid && wr_idma.ready && wr_idma.req.ctl; 
        sync_seq_snk_data = {wr_idma.req.isr, 1'b1};

        idma.valid = wr_idma.valid && wr_idma.ready;
        idma.req.paddr_host = wr_idma.req.paddr_host;
        idma.req.paddr_card = wr_idma.req.paddr_card;
        idma.req.len = wr_idma.req.len;
        idma.req.ctl = wr_idma.req.ctl;
        idma.req.isr = 1'b0;
    end 
    else begin
        rd_idma.ready = idma.ready && sync_seq_snk_ready;
        wr_idma.ready = 1'b0;

        sync_seq_snk_valid = rd_idma.valid && rd_idma.ready && rd_idma.req.ctl; 
        sync_seq_snk_data = {rd_idma.req.isr, 1'b0};

        idma.valid = rd_idma.valid && rd_idma.ready;
        idma.req.paddr_host = rd_idma.req.paddr_host;
        idma.req.paddr_card = rd_idma.req.paddr_card;
        idma.req.len = rd_idma.req.len;
        idma.req.ctl = rd_idma.req.ctl;
        idma.req.isr = 1'b0;
    end
end

endmodule