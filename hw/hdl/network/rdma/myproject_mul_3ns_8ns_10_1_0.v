// 67d7842dbbe25473c3c32b93c0da8047785f30d78e8a024de1b57352245f9689

`timescale 1 ns / 1 ps

  module myproject_mul_3ns_8ns_10_1_0(din0, din1, dout);
parameter ID = 1;
parameter NUM_STAGE = 0;
parameter din0_WIDTH = 14;
parameter din1_WIDTH = 12;
parameter dout_WIDTH = 26;

input [din0_WIDTH - 1 : 0] din0; 
input [din1_WIDTH - 1 : 0] din1; 
output [dout_WIDTH - 1 : 0] dout;

wire signed [dout_WIDTH - 1 : 0] tmp_product;










assign tmp_product = $signed({1'b0, din0}) * $signed({1'b0, din1});











assign dout = tmp_product;







endmodule
