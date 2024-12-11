

module barrel_shifter_axis_512 (
    input logic aclk,
    input logic aresetn,

    input logic enable,

    input logic [511:0] data_in,
    input logic [63:0] keep_in,
    input logic valid_in,
    input logic last_in,
    input logic last_transfer_flag_in,

    output logic [511:0] data_out,
    output logic [63:0] keep_out,
    output logic valid_out,
    output logic last_out,
    output logic last_transfer_flag_out,

    output logic [6:0] offset_out
);

    localparam int PipelineStages = 7;

    // pipeline logic
    logic [511:0] pipeline_data[PipelineStages];
    logic [63:0] pipeline_keep[PipelineStages];
    logic [6:0] pipeline_offset[PipelineStages];
    logic pipeline_last_transfer[PipelineStages];
    logic pipeline_last[PipelineStages];
    logic pipeline_valid[PipelineStages];

    // instantiate bit counter
    // Note that it takes a clock cycle for the offset to read pipeline_offset[0]
    keep_bit_counter_64 bit_counter_inst(
        .aclk(aclk),
        .aresetn(aresetn),
        .keep(keep_in),
        .valid(valid_in & enable),
        .bit_counter(pipeline_offset[0])
    );

    // pipeline stages
    generate
        for (genvar i = 0; i < PipelineStages-1; i++) begin: gen_pipeline_stages
            constant_axis_shifter_512 #(.ShiftAmountBitIndex(i)) inst_shifter (
                .aclk(aclk),
                .aresetn(aresetn),
                .enable(enable),

                .data_in(pipeline_data[i]),
                .keep_in(pipeline_keep[i]),
                .offset_in(pipeline_offset[i]),
                .valid_in(pipeline_valid[i]),
                .last_in(pipeline_last[i]),
                .last_transfer_flag_in(pipeline_last_transfer[i]),

                .data_out(pipeline_data[i+1]),
                .keep_out(pipeline_keep[i+1]),
                .offset_out(pipeline_offset[i+1]),
                .valid_out(pipeline_valid[i+1]),
                .last_out(pipeline_last[i+1]),
                .last_transfer_flag_out(pipeline_last_transfer[i+1])
            );
        end
    endgenerate

    // output assignments
    assign data_out = pipeline_data[PipelineStages-1];
    assign keep_out = pipeline_keep[PipelineStages-1];
    assign valid_out = pipeline_valid[PipelineStages-1];
    assign last_out = pipeline_last[PipelineStages-1];
    assign last_transfer_flag_out = pipeline_last_transfer[PipelineStages-1];
    assign offset_out = pipeline_offset[PipelineStages-1];

    // move the inputs the the first pipeline stage
    always_ff @(posedge aclk) begin
        if (~aresetn) begin
            // reset the first pipeline stage
            // other stages are reset by their constant shifters
            pipeline_data[0] <= 0;
            pipeline_keep[0] <= 0;
            pipeline_last[0] <= 0;
            pipeline_last_transfer[0] <= 0;
            pipeline_valid[0] <= 0;
        end
        else begin
            if (enable) begin
                pipeline_data[0] <= data_in;
                pipeline_keep[0] <= keep_in;
                pipeline_last[0] <= last_in;
                pipeline_last_transfer[0] <= last_transfer_flag_in;
                pipeline_valid[0] <= valid_in;
            end
        end
    end

/* I don't need this ILA for now
`ifndef XILINX_SIMULATOR

    logic [127:0] pipeline_data_signal_0 = {pipeline_data[0][511:448], pipeline_data[0][63:0]};
    logic [127:0] pipeline_data_signal_1 = {pipeline_data[1][511:448], pipeline_data[1][63:0]};
    logic [127:0] pipeline_data_signal_2 = {pipeline_data[2][511:448], pipeline_data[2][63:0]};
    logic [127:0] pipeline_data_signal_3 = {pipeline_data[3][511:448], pipeline_data[3][63:0]};
    logic [127:0] pipeline_data_signal_4 = {pipeline_data[4][511:448], pipeline_data[4][63:0]};
    logic [127:0] pipeline_data_signal_5 = {pipeline_data[5][511:448], pipeline_data[5][63:0]};
    logic [127:0] pipeline_data_signal_6 = {pipeline_data[6][511:448], pipeline_data[6][63:0]};

    ila_pipeline inst_ila_pipeline (
        // data (highest and lowest 64 bits)
        .probe0(pipeline_data_signal_0),
        .probe1(pipeline_data_signal_1),
        .probe2(pipeline_data_signal_2),
        .probe3(pipeline_data_signal_3),
        .probe4(pipeline_data_signal_4),
        .probe5(pipeline_data_signal_5),
        .probe6(pipeline_data_signal_6),
        // keep
        .probe7(pipeline_keep[0]),
        .probe8(pipeline_keep[1]),
        .probe9(pipeline_keep[2]),
        .probe10(pipeline_keep[3]),
        .probe11(pipeline_keep[4]),
        .probe12(pipeline_keep[5]),
        .probe13(pipeline_keep[6]),
        // offset
        .probe14(pipeline_offset[0]),
        .probe15(pipeline_offset[1]),
        .probe16(pipeline_offset[2]),
        .probe17(pipeline_offset[3]),
        .probe18(pipeline_offset[4]),
        .probe19(pipeline_offset[5]),
        .probe20(pipeline_offset[6]),
        // trigger
        .probe21(enable & (pipeline_valid[0] | pipeline_valid[1] | pipeline_valid[2]
            | pipeline_valid[3] | pipeline_valid[4] | pipeline_valid[5] | pipeline_valid[6])),

        .clk(aclk)
    );
`endif
*/
endmodule
