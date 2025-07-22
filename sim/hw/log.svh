/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

`ifndef LOG_SVH
`define LOG_SVH

function string filename_from_path(input string path);
    int i;
 
    for (i = path.len() - 1; i > 0; i = i - 1) begin
        if (path[i] == "/") begin
            i++;
            break;
        end
    end
    return path.substr(i, path.len() - 1);
endfunction

`define DEBUG(MESG) $display("%0t: [DEBUG] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define ERROR(MESG) $error("%0t: [ERROR] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define FATAL(MESG) $fatal(1, "%0t: [FATAL] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`define ASSERT(COND, MESG) assert(COND) else $fatal(1, "%0t: [ASSERT] %s:%0d: %s", $realtime, filename_from_path(`__FILE__), `__LINE__ , $sformatf MESG);
`ifdef EN_VERBOSE
    `define VERBOSE(MESG) `DEBUG(MESG)
`else
    `define VERBOSE(MESG) while (0) begin end
`endif

`endif // LOG_SVH
