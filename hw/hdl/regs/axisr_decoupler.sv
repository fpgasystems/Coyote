import lynxTypes::*;

module axisr_decoupler (
    input  logic [N_REGIONS-1:0]    decouple,

    AXI4SR.s                        axis_in [N_REGIONS],
    AXI4SR.m                        axis_out [N_REGIONS]
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Decoupling --------------------------------------------------------------------------------------------------------- 
// -----------------------------------------------------------------------------------------------------------------------
logic [N_REGIONS-1:0]                        axis_in_tvalid;
logic [N_REGIONS-1:0]                        axis_in_tready;
logic [N_REGIONS-1:0][AXI_DATA_BITS-1:0]     axis_in_tdata;
logic [N_REGIONS-1:0][AXI_DATA_BITS/8-1:0]   axis_in_tkeep;
logic [N_REGIONS-1:0]                        axis_in_tlast;
logic [N_REGIONS-1:0][3:0]                   axis_in_tdest;

logic [N_REGIONS-1:0]                        axis_out_tvalid;
logic [N_REGIONS-1:0]                        axis_out_tready;
logic [N_REGIONS-1:0][AXI_DATA_BITS-1:0]     axis_out_tdata;
logic [N_REGIONS-1:0][AXI_DATA_BITS/8-1:0]   axis_out_tkeep;
logic [N_REGIONS-1:0]                        axis_out_tlast;
logic [N_REGIONS-1:0][3:0]                   axis_out_tdest;

// Assign
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign axis_in_tvalid[i] = axis_in[i].tvalid;
    assign axis_in_tdata[i] = axis_in[i].tdata;
    assign axis_in_tkeep[i] = axis_in[i].tkeep;
    assign axis_in_tlast[i] = axis_in[i].tlast;
    assign axis_in_tdest[i] = axis_in[i].tdest;
    assign axis_in[i].tready = axis_in_tready[i];

    assign axis_out[i].tvalid = axis_out_tvalid[i];
    assign axis_out[i].tdata = axis_out_tdata[i];
    assign axis_out[i].tkeep = axis_out_tkeep[i];
    assign axis_out[i].tlast = axis_out_tlast[i];
    assign axis_out[i].tdest = axis_out_tdest[i];
    assign axis_out_tready[i] = axis_out[i].tready;
end

// Decoupler
for(genvar i = 0; i < N_REGIONS; i++) begin
    assign axis_out_tvalid[i] = decouple[i] ? 1'b0 : axis_in_tvalid[i];
    assign axis_in_tready[i] = decouple[i] ? 1'b0 : axis_out_tready[i];

    assign axis_out_tdata[i] = axis_in_tdata[i];
    assign axis_out_tlast[i] = axis_in_tlast[i];
    assign axis_out_tkeep[i] = axis_in_tkeep[i];
    assign axis_out_tdest[i] = axis_in_tdest[i];
end

endmodule