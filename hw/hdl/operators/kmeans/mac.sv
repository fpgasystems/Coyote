// Copyright (c) 2001-2018 Intel Corporation
//  
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//  
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//  
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
// CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module  logic_dsp_unsigned_27x27_atom 
   (
      input wire           clk_i,
      input wire           clr,
      input wire [26:0]    ax,
      input wire [26:0]    ay,
      input wire           accu_en,
      output wire [53:0]   resulta
   );

   wire [2:0] clk = {clk_i, clk_i, clk_i};
   wire [1:0] aclr = {clr, clr};
   wire [2:0] ena = 3'b111;
  

   twentynm_mac twentynm_mac_component 
   (
      .aclr   (aclr),
      .ax     (ax),
      .ay     (ay),
      .clk    (clk),
      .ena    (ena),
      .resulta(resulta),
      .accumulate(accu_en)
   );
   defparam
      twentynm_mac_component.ax_width = 27,
      twentynm_mac_component.ay_scan_in_width = 27,
      twentynm_mac_component.operation_mode = "m27x27",
      twentynm_mac_component.mode_sub_location = 0,
      twentynm_mac_component.operand_source_max = "input",
      twentynm_mac_component.operand_source_may = "input",
      twentynm_mac_component.operand_source_mbx = "input",
      twentynm_mac_component.operand_source_mby = "input",
      twentynm_mac_component.signed_max = "false",
      twentynm_mac_component.signed_may = "false",
      twentynm_mac_component.signed_mbx = "false",
      twentynm_mac_component.signed_mby = "false",
      twentynm_mac_component.preadder_subtract_a = "false",
      twentynm_mac_component.preadder_subtract_b = "false",
      twentynm_mac_component.ay_use_scan_in = "false",
      twentynm_mac_component.by_use_scan_in = "false",
      twentynm_mac_component.delay_scan_out_ay = "false",
      twentynm_mac_component.delay_scan_out_by = "false",
      twentynm_mac_component.use_chainadder = "false",
      twentynm_mac_component.enable_double_accum = "false",
      twentynm_mac_component.load_const_value = 0,
      twentynm_mac_component.coef_a_0 = 0,
      twentynm_mac_component.coef_a_1 = 0,
      twentynm_mac_component.coef_a_2 = 0,
      twentynm_mac_component.coef_a_3 = 0,
      twentynm_mac_component.coef_a_4 = 0,
      twentynm_mac_component.coef_a_5 = 0,
      twentynm_mac_component.coef_a_6 = 0,
      twentynm_mac_component.coef_a_7 = 0,
      twentynm_mac_component.coef_b_0 = 0,
      twentynm_mac_component.coef_b_1 = 0,
      twentynm_mac_component.coef_b_2 = 0,
      twentynm_mac_component.coef_b_3 = 0,
      twentynm_mac_component.coef_b_4 = 0,
      twentynm_mac_component.coef_b_5 = 0,
      twentynm_mac_component.coef_b_6 = 0,
      twentynm_mac_component.coef_b_7 = 0,
      twentynm_mac_component.ax_clock = "0",
      twentynm_mac_component.ay_scan_in_clock = "0",
      twentynm_mac_component.az_clock = "none",
      twentynm_mac_component.bx_clock = "none",
      twentynm_mac_component.by_clock = "none",
      twentynm_mac_component.bz_clock = "none",
      twentynm_mac_component.coef_sel_a_clock = "none",
      twentynm_mac_component.coef_sel_b_clock = "none",
      twentynm_mac_component.sub_clock = "none",
      twentynm_mac_component.sub_pipeline_clock = "none",
      twentynm_mac_component.negate_clock = "none",
      twentynm_mac_component.negate_pipeline_clock = "none",
      twentynm_mac_component.accumulate_clock = "none",
      twentynm_mac_component.accum_pipeline_clock = "none",
      twentynm_mac_component.load_const_clock = "none",
      twentynm_mac_component.load_const_pipeline_clock = "none",
      twentynm_mac_component.input_pipeline_clock = "none",
      twentynm_mac_component.output_clock = "0",
      twentynm_mac_component.scan_out_width = 18,
      twentynm_mac_component.result_a_width = 54;
endmodule