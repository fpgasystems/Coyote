// I/O
AXI4SR axis_sink_int ();
AXI4L axi_ctrl_int ();

always_comb axis_host_0_src.tie_off_m();

axisr_reg_rtl inst_reg_slice_sink (.aclk(aclk), .aresetn(aresetn), .s_axis(axis_host_0_sink), .m_axis(axis_sink_int));
axil_reg_rtl inst_reg_slice_ctrl (.aclk(aclk), .aresetn(aresetn), .s_axil(axi_ctrl), .m_axil(axi_ctrl_int));


// UL
logic done;
logic select;
logic [39:0] total_sum;
logic [39:0] selected_sum;
logic [31:0] selected_count;

AXI4S axis_data ();
AXI4S axis_predicates ();

// Slave
percentage_slv inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl_int),
    .done(done),
    .select(select),
    .total_sum(total_sum),
    .selected_sum(selected_sum),
    .selected_count(selected_count)
);


// Mux input
always_comb begin
    axis_data.tdata = axis_sink_int.tdata;
    axis_data.tkeep = axis_sink_int.tkeep;
    axis_data.tlast = axis_sink_int.tlast;
    
    axis_predicates.tdata = axis_sink_int.tdata;
    axis_predicates.tkeep = axis_sink_int.tdata;
    axis_predicates.tlast = axis_sink_int.tlast;
    
    if(select) begin
        axis_data.tvalid = axis_sink_int.tvalid;
        axis_predicates.tvalid = 1'b0;

        axis_sink_int.tready = axis_data.tready;
    end
    else begin
        axis_data.tvalid = 1'b0;
        axis_predicates.tvalid = axis_data.tvalid;

        axis_sink_int.tready = axis_predicates.tready;
    end
end

// Minmaxsum
percentage inst_top (
    .clk(aclk),
    .rst_n(aresetn),
    .predicates_line(predicates_tdata),
    .predicates_valid(predicates_tvalid),
    .predicates_last(predicates_tlast),
    .predicates_in_ready(predicates_tready),
    .data_line(data_tdata),
    .data_valid(data_tvalid),
    .data_last(data_tlast),
    .data_in_ready(data_tready),
    .total_sum(total_sum),
    .selected_sum(selected_sum),
    .selected_count(selected_count),
    .output_valid(done)
);