

module constant_axis_shifter_512 #(
    parameter int ShiftAmountBitIndex = 0
) (
    input logic aclk,
    input logic aresetn,
    input logic enable,

    input logic [511:0] data_in,
    input logic [63:0] keep_in,
    input logic [6:0] offset_in,
    input logic valid_in,
    input logic last_in,
    input logic last_transfer_flag_in,

    output logic [511:0] data_out,
    output logic [63:0] keep_out,
    output logic [6:0] offset_out,
    output logic valid_out,
    output logic last_out,
    output logic last_transfer_flag_out
);

    // calculate the shift amount from the bit index
    localparam int DataShiftAmount = 32'd8 << ShiftAmountBitIndex;
    localparam int KeepShiftAmount = 32'd1 << ShiftAmountBitIndex;

    logic [6:0] offset;
    assign offset_out = offset;

    always_ff @(posedge aclk) begin
        // check for reset
        if (~aresetn) begin
            data_out <= 0;
            keep_out <= 0;
            valid_out <= 0;
            last_out <= 0;
            last_transfer_flag_out <= 0;
            offset <= 0;
        end
        else begin
            if (enable) begin
                // check if corresponding bit is set
                if (offset[ShiftAmountBitIndex]) begin
                    // bit is set, so shift
                    data_out <= {data_in[511-DataShiftAmount:0], data_in[511:512-DataShiftAmount]};
                    keep_out <= {keep_in[63-KeepShiftAmount:0], keep_in[63:64-KeepShiftAmount]};
                end
                else begin
                    // bit is not set, so don't shift
                    data_out <= data_in;
                    keep_out <= keep_in;
                end

                // unconditional assignments
                offset <= offset_in;
                valid_out <= valid_in;
                last_out <= last_in;
                last_transfer_flag_out <= last_transfer_flag_in;
            end
        end
    end

endmodule
