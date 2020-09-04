import lynxTypes::*;

/**
 *	TLB assign when single region present
 */ 
module tlb_assign_isr #(
    parameter integer RDWR = 0
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    dmaIsrIntf.s                        req_snk,
    dmaIntf.m                           req_src_host,
    dmaIntf.m                           req_src_card
);

// Assign
always_comb begin

    req_snk.ready = req_src_host.ready & req_src_card.ready;
    if(RDWR == 0)
        req_snk.done = req_src_card.done;
    else
        req_snk.done = req_src_host.done;
    req_snk.isr_return = 1'b0;

    req_src_host.valid = req_snk.valid & req_snk.ready;
    req_src_card.valid = req_snk.valid & req_snk.ready;
    req_src_host.req.paddr = req_snk.req.paddr_host;
    req_src_card.req.paddr = req_snk.req.paddr_card;
    req_src_host.req.len = req_snk.req.len;
    req_src_card.req.len = req_snk.req.len;
    req_src_host.req.ctl = req_snk.req.ctl;
    req_src_card.req.ctl = req_snk.req.ctl;
    req_src_host.req.dest = req_snk.req.dest;
    req_src_card.req.dest = req_snk.req.dest;
end

endmodule