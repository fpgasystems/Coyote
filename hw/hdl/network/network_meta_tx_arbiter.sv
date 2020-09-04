/**
 *	Network meta TX arbiter - Round Robin
 */ 

import lynxTypes::*;

module network_meta_tx_arbiter #( 
    parameter integer DATA_BITS         = 32
) (
	input  logic    					aclk,    
	input  logic    					aresetn,

	// User logic
    metaIntf.s                           meta_snk [N_REGIONS],
    metaIntf.m                           meta_src,

    // ID
    output logic [N_REQUEST_BITS-1:0]   id
);

logic [N_REGIONS-1:0] ready_snk;
logic [N_REGIONS-1:0] valid_snk;
logic [N_REGIONS-1:0][DATA_BITS-1:0] data_snk;
logic ready_src;
logic valid_src;
logic [DATA_BITS-1:0] data_src;

logic [N_REQUEST_BITS-1:0] rr_reg;

// -------------------------------------------------------------------------------- 
// I/O !!! interface 
// -------------------------------------------------------------------------------- 
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign valid_snk[i] = meta_snk[i].valid;
    assign meta_snk[i].ready = ready_snk[i];
    assign data_snk[i] = meta_snk[i].data;    
end

assign meta_src.valid = valid_src;
assign ready_src = meta_src.ready;
assign meta_src.data = data_src;

// -------------------------------------------------------------------------------- 
// RR 
// -------------------------------------------------------------------------------- 
always_ff @(posedge aclk or negedge aresetn) begin
	if(aresetn == 1'b0) begin
		rr_reg <= 0;
	end else begin
        if(valid_src & ready_src) begin 
            rr_reg <= rr_reg + 1;
            if(rr_reg >= N_REGIONS-1)
                rr_reg <= 0;
        end
	end
end

// DP
always_comb begin
    ready_snk = 0;
    valid_src = 1'b0;
    id = 0;
    
    for(int i = 0; i < N_REGIONS; i++) begin
        if(i+rr_reg >= N_REGIONS) begin
            if(valid_snk[i+rr_reg-N_REGIONS]) begin
                valid_src = valid_snk[i+rr_reg-N_REGIONS];
                id = i+rr_reg-N_REGIONS;
                break;
            end
        end
        else begin
            if(valid_snk[i+rr_reg]) begin
                valid_src = valid_snk[i+rr_reg];
                id = i+rr_reg;
                break;
            end
        end
    end

    ready_snk[id] = ready_src;
    data_src = data_snk[id];
end

endmodule