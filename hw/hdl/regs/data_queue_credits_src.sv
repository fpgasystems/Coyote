import lynxTypes::*;

module data_queue_credits_src #(
	parameter integer 		DATA_BITS = AXI_DATA_BITS	
) (
	input  logic 			aclk,
	input  logic 			aresetn,
	
	AXI4S.s 				axis_in,
	AXI4SR.m 				axis_out,
    input  logic [3:0]      rd_dest
);

if(N_DDR_CHAN == 1) begin
    axis_data_fifo_512 inst_data (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_in.tvalid),
        .s_axis_tready(axis_in.tready),
        .s_axis_tdata(axis_in.tdata),
        .s_axis_tkeep(axis_in.tkeep),
        .s_axis_tlast(axis_in.tlast),
        .m_axis_tvalid(axis_out.tvalid),
        .m_axis_tready(axis_out.tready),
        .m_axis_tdata(axis_out.tdata),
        .m_axis_tkeep(axis_out.tkeep),
        .m_axis_tlast(axis_out.tlast)
    );
end
else if(N_DDR_CHAN == 2) begin
    axis_data_fifo_1k inst_data (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_in.tvalid),
        .s_axis_tready(axis_in.tready),
        .s_axis_tdata(axis_in.tdata),
        .s_axis_tkeep(axis_in.tkeep),
        .s_axis_tlast(axis_in.tlast),
        .m_axis_tvalid(axis_out.tvalid),
        .m_axis_tready(axis_out.tready),
        .m_axis_tdata(axis_out.tdata),
        .m_axis_tkeep(axis_out.tkeep),
        .m_axis_tlast(axis_out.tlast)
    );
end
else begin
    axis_data_fifo_2k inst_data (
        .s_axis_aresetn(aresetn),
        .s_axis_aclk(aclk),
        .s_axis_tvalid(axis_in.tvalid),
        .s_axis_tready(axis_in.tready),
        .s_axis_tdata(axis_in.tdata),
        .s_axis_tkeep(axis_in.tkeep),
        .s_axis_tlast(axis_in.tlast),
        .m_axis_tvalid(axis_out.tvalid),
        .m_axis_tready(axis_out.tready),
        .m_axis_tdata(axis_out.tdata),
        .m_axis_tkeep(axis_out.tkeep),
        .m_axis_tlast(axis_out.tlast)
    );
end

assign axis_out.tdest = rd_dest;

endmodule

