import lynxTypes::*;

module req_decoupler (
	input  logic [N_REGIONS-1:0]	decouple,

	reqIntf.s 						req_in [N_REGIONS],
	reqIntf.m 						req_out [N_REGIONS]
);
    // ----------------------------------------------------------------------------------------------------------------------- 
	// -- Decoupling --------------------------------------------------------------------------------------------------------- 
	// ----------------------------------------------------------------------------------------------------------------------- 
    genvar i;
    generate
    for(i = 0; i < N_REGIONS; i++) begin
        assign req_out[i].valid   = decouple[i] ? 1'b0 : req_in[i].valid;
        assign req_in[i].ready    = decouple[i] ? 1'b0 : req_out[i].ready;

        assign req_out[i].req = req_in[i].req;
    end
    endgenerate

endmodule