`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * User logic
 * 
 */
module design_user_logic_0 (
    // Clock and reset
    input  wire                 aclk,
    input  wire[0:0]            aresetn,

    // AXI4 control
    AXI4L.s                     axi_ctrl,

    // AXI4S
    AXI4S.m                     axis_src,
    AXI4S.s                     axis_sink
);

/* -- Tie-off unused interfaces and signals ----------------------------- */
//always_comb axi_ctrl.tie_off_s();
always_comb axis_src.tie_off_m();
//always_comb axis_sink.tie_off_s();

/* -- USER LOGIC -------------------------------------------------------- */
// Reg input
AXI4S axis_sink_r ();
//AXI4S axis_src_r ();
axis_reg_rtl inst_reg_sink (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_sink), .axis_out(axis_sink_r));
//axis_reg_rtl inst_reg_src (.aclk(aclk), .aresetn(aresetn), .axis_in(axis_src_r), .axis_out(axis_src));

logic clr;
logic done;
logic select;
logic [39:0] total_sum;
logic [39:0] selected_sum;
logic [31:0] selected_count;

AXI4S axis_data ();
AXI4S axis_predicates ();

// Slave
percentage_slave inst_slave (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .clr(clr),
    .done(done),
    .select(select),
    .minimum(minimum),
    .maximum(maximum),
    .summation(summation)
);

// Mux input
always_comb begin
    axis_data.tdata = axis_sink_r.tdata;
    axis_data.tkeep = axis_sink_r.tkeep;
    axis_data.tlast = axis_sink_r.tlast;
    
    axis_predicates.tdata = axis_sink_r.tdata;
    axis_predicates.tkeep = axis_sink_r.tdata;
    axis_predicates.tlast = axis_sink_r.tlast;
    
    if(select) begin
        axis_data.tvalid = axis_sink_r.tvalid;
        axis_predicates.tvalid = 1'b0;

        axis_sink_r.tready = axis_data.tready;
    end
    else begin
        axis_data.tvalid = 1'b0;
        axis_predicates.tvalid = axis_data.tvalid;

        axis_sink_r.tready = axis_predicates.tready;
    end
end

// FIFO predicates

// FIFO data

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

endmodule
