`timescale 1ns / 1ps

import lynxTypes::*;

module meta_decoupler (
	input  logic [N_REGIONS-1:0]	decouple,

	metaIntf.s 						s_meta [N_REGIONS],
	metaIntf.m 						m_meta [N_REGIONS]
);
    // ----------------------------------------------------------------------------------------------------------------------- 
	// -- Decoupling --------------------------------------------------------------------------------------------------------- 
	// ----------------------------------------------------------------------------------------------------------------------- 
    genvar i;
    generate
    for(i = 0; i < N_REGIONS; i++) begin
        assign m_meta[i].valid   = decouple[i] ? 1'b0 : s_meta[i].valid;
        assign s_meta[i].ready    = decouple[i] ? 1'b0 : m_meta[i].ready;

        assign m_meta[i].data = s_meta[i].data;
    end
    endgenerate

endmodule