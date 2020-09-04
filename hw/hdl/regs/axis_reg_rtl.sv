import lynxTypes::*;

//`define XILINX_REG

module axis_reg_rtl #(
	parameter integer 		REG_DATA_BITS = AXI_DATA_BITS	
) (
	input logic 			aclk,
	input logic 			aresetn,
	
	AXI4S.s 				axis_in,
	AXI4S.m 				axis_out
);

// Internal registers
logic axis_in_tready_C, axis_in_tready_N;

logic [REG_DATA_BITS-1:0] axis_out_tdata_C, axis_out_tdata_N;
logic [(REG_DATA_BITS/8)-1:0] axis_out_tkeep_C, axis_out_tkeep_N;
logic axis_out_tvalid_C, axis_out_tvalid_N;
logic axis_out_tlast_C, axis_out_tlast_N;

logic [REG_DATA_BITS-1:0] tmp_tdata_C, tmp_tdata_N;
logic [(REG_DATA_BITS/8)-1:0] tmp_tkeep_C, tmp_tkeep_N;
logic tmp_tvalid_C, tmp_tvalid_N;
logic tmp_tlast_C, tmp_tlast_N;

// Comb
assign axis_in_tready_N  = axis_out.tready || (!tmp_tvalid_C && (!axis_out_tvalid_C || !axis_in.tvalid));

always_comb begin
	axis_out_tvalid_N = axis_out_tvalid_C;
	axis_out_tdata_N = axis_out_tdata_C;
	axis_out_tkeep_N = axis_out_tkeep_C;
	axis_out_tlast_N = axis_out_tlast_C;

	tmp_tvalid_N = tmp_tvalid_C;
	tmp_tdata_N = tmp_tdata_C;
	tmp_tkeep_N = tmp_tkeep_C;
	tmp_tlast_N = tmp_tlast_C;

	if(axis_in_tready_C) begin
		if(axis_out.tready || !axis_out_tvalid_C) begin
			axis_out_tvalid_N = axis_in.tvalid;
			axis_out_tdata_N = axis_in.tdata;
			axis_out_tkeep_N = axis_in.tkeep;
			axis_out_tlast_N = axis_in.tlast;
		end
		else begin
			tmp_tvalid_N = axis_in.tvalid;
			tmp_tdata_N = axis_in.tdata;
			tmp_tkeep_N = axis_in.tkeep;
			tmp_tlast_N = axis_in.tlast;
		end
	end
	else if(axis_out.tready) begin
		axis_out_tvalid_N = tmp_tvalid_C;
		axis_out_tdata_N = tmp_tdata_C;
		axis_out_tkeep_N = tmp_tkeep_C;
		axis_out_tlast_N = tmp_tlast_C;

		tmp_tvalid_N = 1'b0;
	end
end

// Reg process
always_ff @(posedge aclk, negedge aresetn) begin
	if(aresetn == 1'b0) begin
		axis_out_tdata_C <= 0;
		axis_out_tkeep_C <= 0;
		axis_out_tlast_C <= 0;
		axis_out_tvalid_C <= 0;
		tmp_tdata_C <= 0;
		tmp_tkeep_C <= 0;
		tmp_tlast_C <= 0;
		tmp_tvalid_C <= 0;
		axis_in_tready_C <= 0;
	end 
	else begin 
		axis_out_tdata_C <= axis_out_tdata_N;
		axis_out_tkeep_C <= axis_out_tkeep_N;
		axis_out_tlast_C <= axis_out_tlast_N;
		axis_out_tvalid_C <= axis_out_tvalid_N;
		tmp_tdata_C <= tmp_tdata_N;
		tmp_tkeep_C <= tmp_tkeep_N;
		tmp_tlast_C <= tmp_tlast_N;
		tmp_tvalid_C <= tmp_tvalid_N;
		axis_in_tready_C <= axis_in_tready_N;
	end
end

// Outputs
assign axis_in.tready = axis_in_tready_C;

assign axis_out.tdata = axis_out_tdata_C;
assign axis_out.tkeep = axis_out_tkeep_C;
assign axis_out.tlast = axis_out_tlast_C;
assign axis_out.tvalid = axis_out_tvalid_C;

endmodule