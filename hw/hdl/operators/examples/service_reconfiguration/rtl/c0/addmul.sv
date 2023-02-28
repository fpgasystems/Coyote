import lynxTypes::*;

module addmul #(
    parameter integer ADDMUL_DATA_BITS = AXI_DATA_BITS     
) (
    input  logic                aclk,
    input  logic                aresetn,

    input  logic [15:0]         mul_factor,
    input  logic [15:0]         add_factor,

    AXI4SR.s                    axis_in,
    AXI4SR.m                    axis_out
);

localparam integer N_INTS = ADDMUL_DATA_BITS / 32;

logic [1:0] val_C = 0;
logic [N_INTS-1:0][31:0] mul_C = 0;
logic [N_INTS-1:0][31:0] add_C = 0;

logic [1:0][ADDMUL_DATA_BITS/8-1:0] keep_C = 0;
logic [1:0] last_C = 0;

always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        val_C <= 0;
        keep_C <= 0;
        last_C <= 0;
    end 
    else begin
        if(axis_out.tready) begin
            val_C[0] <= axis_in.tvalid;
            keep_C[0] <= axis_in.tkeep;
            last_C[0] <= axis_in.tlast;

            val_C[1] <= val_C[0];
            keep_C[1] <= keep_C[0];
            last_C[1] <= last_C[0];
        end
    end
end

for(genvar i = 0; i < N_INTS; i++) begin
    always_ff @(posedge aclk) begin
        if(aresetn == 1'b0) begin
            mul_C[i] <= 0;
            add_C[i] <= 0;
        end 
        else begin
            if(axis_out.tready) begin
                mul_C[i] <= axis_in.tdata[i*32+:32] << mul_factor;
                add_C[i] <= mul_C[i] + add_factor;
            end
        end
    end

    assign axis_out.tdata[i*32+:32] = add_C[i];
end

assign axis_in.tready = axis_out.tready;

assign axis_out.tkeep = keep_C[1];
assign axis_out.tlast = last_C[1];
assign axis_out.tvalid = val_C[1];
assign axis_out.tid = 0;

endmodule 