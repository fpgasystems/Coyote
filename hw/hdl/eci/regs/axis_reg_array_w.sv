import eci_cmd_defs::*;
import block_types::*;

import lynxTypes::*;

module axis_reg_array_w #(
    parameter integer                   N_STAGES = 2  
) (
	input  logic 			            aclk,
	input  logic 			            aresetn,
	
	input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic [ECI_CL_WIDTH-1:0]    s_axis_tdata,
    input  logic [ECI_CL_WIDTH/8-1:0]  s_axis_tstrb,
    input  logic                        s_axis_tlast,

    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic [ECI_CL_WIDTH-1:0]    m_axis_tdata,
    output logic [ECI_CL_WIDTH/8-1:0]  m_axis_tstrb,
    output logic                        m_axis_tlast
);

logic [N_STAGES:0][ECI_CL_WIDTH-1:0] axis_tdata;
logic [N_STAGES:0] axis_tvalid;
logic [N_STAGES:0] axis_tready;
logic [N_STAGES:0][ECI_CL_WIDTH/8-1:0] axis_tstrb;
logic [N_STAGES:0] axis_tlast;

assign axis_tdata[0] = s_axis_tdata;
assign axis_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_tready[0];
assign axis_tstrb[0] = s_axis_tstrb;
assign axis_tlast[0] = s_axis_tlast;

assign m_axis_tdata = axis_tdata[N_STAGES];
assign m_axis_tvalid = axis_tvalid[N_STAGES];
assign axis_tready[N_STAGES] = m_axis_tready;
assign m_axis_tstrb = axis_tstrb[N_STAGES];
assign m_axis_tlast = axis_tlast[N_STAGES];

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_register_slice_w inst_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tvalid[i]),
        .s_axis_tready(axis_tready[i]),
        .s_axis_tdata(axis_tdata[i]),
        .s_axis_tstrb(axis_tstrb[i]),
        .s_axis_tlast(axis_tlast[i]),
        .m_axis_tvalid(axis_tvalid[i+1]),
        .m_axis_tready(axis_tready[i+1]),
        .m_axis_tdata(axis_tdata[i+1]),
        .m_axis_tstrb(axis_tstrb[i+1]),
        .m_axis_tlast(axis_tlast[i+1])
    );
end

endmodule