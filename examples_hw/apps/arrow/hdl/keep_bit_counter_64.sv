


module keep_bit_counter_64 (
    input logic aclk,
    input logic aresetn,
    input logic [63:0] keep,
    input logic valid,
    output logic [6:0] bit_counter
);

    logic [6:0] state;
    assign bit_counter = state;

    always_ff @(posedge aclk) begin
        // check for reset
        if (~aresetn) begin
            state <= 0;
        end
        else begin
            if (valid) begin
                case (keep)
                    64'h0000000000000000: state <= {1'b0, state[5:0]} + 64'd00;
                    64'h0000000000000001: state <= {1'b0, state[5:0]} + 64'd01;
                    64'h0000000000000003: state <= {1'b0, state[5:0]} + 64'd02;
                    64'h0000000000000007: state <= {1'b0, state[5:0]} + 64'd03;
                    64'h000000000000000f: state <= {1'b0, state[5:0]} + 64'd04;
                    64'h000000000000001f: state <= {1'b0, state[5:0]} + 64'd05;
                    64'h000000000000003f: state <= {1'b0, state[5:0]} + 64'd06;
                    64'h000000000000007f: state <= {1'b0, state[5:0]} + 64'd07;
                    64'h00000000000000ff: state <= {1'b0, state[5:0]} + 64'd08;
                    64'h00000000000001ff: state <= {1'b0, state[5:0]} + 64'd09;
                    64'h00000000000003ff: state <= {1'b0, state[5:0]} + 64'd10;
                    64'h00000000000007ff: state <= {1'b0, state[5:0]} + 64'd11;
                    64'h0000000000000fff: state <= {1'b0, state[5:0]} + 64'd12;
                    64'h0000000000001fff: state <= {1'b0, state[5:0]} + 64'd13;
                    64'h0000000000003fff: state <= {1'b0, state[5:0]} + 64'd14;
                    64'h0000000000007fff: state <= {1'b0, state[5:0]} + 64'd15;
                    64'h000000000000ffff: state <= {1'b0, state[5:0]} + 64'd16;
                    64'h000000000001ffff: state <= {1'b0, state[5:0]} + 64'd17;
                    64'h000000000003ffff: state <= {1'b0, state[5:0]} + 64'd18;
                    64'h000000000007ffff: state <= {1'b0, state[5:0]} + 64'd19;
                    64'h00000000000fffff: state <= {1'b0, state[5:0]} + 64'd20;
                    64'h00000000001fffff: state <= {1'b0, state[5:0]} + 64'd21;
                    64'h00000000003fffff: state <= {1'b0, state[5:0]} + 64'd22;
                    64'h00000000007fffff: state <= {1'b0, state[5:0]} + 64'd23;
                    64'h0000000000ffffff: state <= {1'b0, state[5:0]} + 64'd24;
                    64'h0000000001ffffff: state <= {1'b0, state[5:0]} + 64'd25;
                    64'h0000000003ffffff: state <= {1'b0, state[5:0]} + 64'd26;
                    64'h0000000007ffffff: state <= {1'b0, state[5:0]} + 64'd27;
                    64'h000000000fffffff: state <= {1'b0, state[5:0]} + 64'd28;
                    64'h000000001fffffff: state <= {1'b0, state[5:0]} + 64'd29;
                    64'h000000003fffffff: state <= {1'b0, state[5:0]} + 64'd30;
                    64'h000000007fffffff: state <= {1'b0, state[5:0]} + 64'd31;
                    64'h00000000ffffffff: state <= {1'b0, state[5:0]} + 64'd32;
                    64'h00000001ffffffff: state <= {1'b0, state[5:0]} + 64'd33;
                    64'h00000003ffffffff: state <= {1'b0, state[5:0]} + 64'd34;
                    64'h00000007ffffffff: state <= {1'b0, state[5:0]} + 64'd35;
                    64'h0000000fffffffff: state <= {1'b0, state[5:0]} + 64'd36;
                    64'h0000001fffffffff: state <= {1'b0, state[5:0]} + 64'd37;
                    64'h0000003fffffffff: state <= {1'b0, state[5:0]} + 64'd38;
                    64'h0000007fffffffff: state <= {1'b0, state[5:0]} + 64'd39;
                    64'h000000ffffffffff: state <= {1'b0, state[5:0]} + 64'd40;
                    64'h000001ffffffffff: state <= {1'b0, state[5:0]} + 64'd41;
                    64'h000003ffffffffff: state <= {1'b0, state[5:0]} + 64'd42;
                    64'h000007ffffffffff: state <= {1'b0, state[5:0]} + 64'd43;
                    64'h00000fffffffffff: state <= {1'b0, state[5:0]} + 64'd44;
                    64'h00001fffffffffff: state <= {1'b0, state[5:0]} + 64'd45;
                    64'h00003fffffffffff: state <= {1'b0, state[5:0]} + 64'd46;
                    64'h00007fffffffffff: state <= {1'b0, state[5:0]} + 64'd47;
                    64'h0000ffffffffffff: state <= {1'b0, state[5:0]} + 64'd48;
                    64'h0001ffffffffffff: state <= {1'b0, state[5:0]} + 64'd49;
                    64'h0003ffffffffffff: state <= {1'b0, state[5:0]} + 64'd50;
                    64'h0007ffffffffffff: state <= {1'b0, state[5:0]} + 64'd51;
                    64'h000fffffffffffff: state <= {1'b0, state[5:0]} + 64'd52;
                    64'h001fffffffffffff: state <= {1'b0, state[5:0]} + 64'd53;
                    64'h003fffffffffffff: state <= {1'b0, state[5:0]} + 64'd54;
                    64'h007fffffffffffff: state <= {1'b0, state[5:0]} + 64'd55;
                    64'h00ffffffffffffff: state <= {1'b0, state[5:0]} + 64'd56;
                    64'h01ffffffffffffff: state <= {1'b0, state[5:0]} + 64'd57;
                    64'h03ffffffffffffff: state <= {1'b0, state[5:0]} + 64'd58;
                    64'h07ffffffffffffff: state <= {1'b0, state[5:0]} + 64'd59;
                    64'h0fffffffffffffff: state <= {1'b0, state[5:0]} + 64'd60;
                    64'h1fffffffffffffff: state <= {1'b0, state[5:0]} + 64'd61;
                    64'h3fffffffffffffff: state <= {1'b0, state[5:0]} + 64'd62;
                    64'h7fffffffffffffff: state <= {1'b0, state[5:0]} + 64'd63;
                    64'hffffffffffffffff: state <= {1'b0, state[5:0]} + 64'd64;
                    default:
                        $display("Invalid Keep bits for bit counter!");
                endcase
            end
        end
    end
endmodule
