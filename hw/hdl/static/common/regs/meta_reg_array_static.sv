/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

`include "lynx_macros.svh"

module meta_reg_array_static #(
    parameter integer                       N_STAGES = 2,
    parameter integer                       DATA_BITS = 32
) (
    input  logic                            aclk,
    input  logic                            aresetn,

    metaIntf.s                              s_meta,
    metaIntf.m                              m_meta
);

// ----------------------------------------------------------------------------------------------------------------------- 
// -- Register slices ---------------------------------------------------------------------------------------------------- 
// ----------------------------------------------------------------------------------------------------------------------- 
metaIntf #(.STYPE(logic[DATA_BITS-1:0])) meta_s [N_STAGES+1] (.*);

`META_ASSIGN(s_meta, meta_s[0])
`META_ASSIGN(meta_s[N_STAGES], m_meta)

for(genvar i = 0; i < N_STAGES; i++) begin
    meta_reg_static #(.DATA_BITS(DATA_BITS)) inst_reg (.aclk(aclk), .aresetn(aresetn), .s_meta(meta_s[i]), .m_meta(meta_s[i+1]));  
end

endmodule