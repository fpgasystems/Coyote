import lynxTypes::*;

module meta_decoupler (
	input  logic [N_REGIONS-1:0]	decouple,

	metaIntf.s 						meta_in [N_REGIONS],
	metaIntf.m 						meta_out [N_REGIONS]
);
    // ----------------------------------------------------------------------------------------------------------------------- 
	// -- Decoupling --------------------------------------------------------------------------------------------------------- 
	// ----------------------------------------------------------------------------------------------------------------------- 
    genvar i;
    generate
    for(i = 0; i < N_REGIONS; i++) begin
        assign meta_out[i].valid   = decouple[i] ? 1'b0 : meta_in[i].valid;
        assign meta_in[i].ready    = decouple[i] ? 1'b0 : meta_out[i].ready;

        assign meta_out[i].data = meta_in[i].data;
    end
    endgenerate

endmodule