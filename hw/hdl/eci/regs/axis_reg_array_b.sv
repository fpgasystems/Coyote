import lynxTypes::*;

module axis_reg_array_b #(
    parameter integer                   N_STAGES = 2  
) (
	input  logic 			            aclk,
	input  logic 			            aresetn,
	
	input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic [1:0]                  s_axis_tuser,

    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic [1:0]                  m_axis_tuser
);

logic [N_STAGES:0][1:0] axis_tuser;
logic [N_STAGES:0] axis_tvalid;
logic [N_STAGES:0] axis_tready;

assign axis_tuser[0] = s_axis_tuser;
assign axis_tvalid[0] = s_axis_tvalid;
assign s_axis_tready = axis_tready[0];

assign m_axis_tuser = axis_tuser[N_STAGES];
assign m_axis_tvalid = axis_tvalid[N_STAGES];
assign axis_tready[N_STAGES] = m_axis_tready;

for(genvar i = 0; i < N_STAGES; i++) begin
    axis_register_slice_b inst_reg_slice (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tvalid(axis_tvalid[i]),
        .s_axis_tready(axis_tready[i]),
        .s_axis_tuser(axis_tuser[i]),
        .m_axis_tvalid(axis_tvalid[i+1]),
        .m_axis_tready(axis_tready[i+1]),
        .m_axis_tuser(axis_tuser[i+1])
    );
end

endmodule