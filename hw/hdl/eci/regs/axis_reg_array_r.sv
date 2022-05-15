import eci_cmd_defs::*;
import block_types::*;

import lynxTypes::*;

module axis_reg_array_r #(
    parameter integer                   N_STAGES = 2  
) (
	input  logic 			            aclk,
	input  logic 			            aresetn,
	
	input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic [ECI_CL_WIDTH-1:0]    s_axis_tdata,

    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic [ECI_CL_WIDTH-1:0]    m_axis_tdata
);

logic [N_STAGES:0][ECI_CL_WIDTH-1:0] axis_tdata;
logic [N_STAGES:0] axis_tvalid;
logic [N_STAGES:0] axis_tready;

assign axis_tdata[0] = s_axis_tdata;
assign axis_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_tready[0];

assign m_axis_tdata = axis_tdata[N_STAGES];
assign m_axis_tvalid = axis_tvalid[N_STAGES];
assign axis_tready[N_STAGES] = m_axis_tready;

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_register_slice_r inst_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tvalid[i]),
        .s_axis_tready(axis_tready[i]),
        .s_axis_tdata(axis_tdata[i]),
        .m_axis_tvalid(axis_tvalid[i+1]),
        .m_axis_tready(axis_tready[i+1]),
        .m_axis_tdata(axis_tdata[i+1])
    );
end

endmodule