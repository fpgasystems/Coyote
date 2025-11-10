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


`ifndef ECI_GET_NUM_WORDS_IN_PKT_C_SV
`define ECI_GET_NUM_WORDS_IN_PKT_C_SV

import eci_cmd_defs::*;

module eci_get_num_words_in_pkt_c (
    input  eci_word_t eci_command,
    output logic [ECI_PACKET_SIZE_WIDTH-1:0] num_words_in_pkt 
);

   logic [ECI_PACKET_SIZE_WIDTH-1:0] num_words;

   eci_dmask_t this_dmask;
   logic [ECI_SCL_WIDTH-1:0] this_num_scl;

   assign this_dmask   = eci_command.generic_cmd.dmask;
   assign this_num_scl = get_scl_from_dmask( this_dmask );
   
   assign num_words_in_pkt = get_num_words_from_scl( this_num_scl );

endmodule // eci_get_num_words_in_pkt


`endif
