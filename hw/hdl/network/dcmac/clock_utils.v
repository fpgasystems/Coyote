
/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

`timescale 1ns / 1ps

module clk_to_serdes_clk (
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) input  clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:gt_usrclk:1.0 serdes_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME serdes_clk, FREQ_HZ 664062000, PARENT_ID undef, PHASE 0.0" *) output wire [5:0] serdes_clk
);

    assign serdes_clk = {1'b0, 1'b0, 1'b0, 1'b0, clk, clk};

endmodule

module clk_to_alt_serdes_clk (
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) input  clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:gt_usrclk:1.0 serdes_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME serdes_clk, FREQ_HZ 332031000, PARENT_ID undef, PHASE 0.0" *) output wire [5:0] serdes_clk
);

    assign serdes_clk = {1'b0, 1'b0, 1'b0, 1'b0, clk, clk};

endmodule

module clk_to_ts_clk (
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) input  clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ts_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ts_clk, FREQ_HZ 100000000" *) output wire [5:0] ts_clk
);

    assign ts_clk = {6{clk}};

endmodule

module clk_to_flexif_clk (
	(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) input  clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 flexif_clk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME flexif_clk, FREQ_HZ 390625000" *) output wire [5:0] flexif_clk
);

    assign flexif_clk = {6{clk}};

endmodule
