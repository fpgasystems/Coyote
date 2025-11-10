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

import lynxTypes::*;

// We need these classes instead of just using the structs because structs do not have a constructor and thus always the same reference of the struct is passed to a mailboxes causing bugs in Vivado < 2024.2

class c_trs_req;
    typedef struct packed {
        byte last;
        longint len;
        longint vaddr;
        byte dest;
        byte strm;
        byte opcode;
    } binary_format_t; // Values are the other way around in the binary format because they are serialized like this

    static int BYTES = $bits(binary_format_t) / 8;

    req_t data;
    realtime req_time;

    function new();
        data = 0;
        req_time = $realtime;
    endfunction

    function void initialize(input logic[511:0] data);
        binary_format_t raw = data[$bits(binary_format_t) - 1:0];

        this.data.opcode = raw.opcode;
        this.data.strm   = raw.strm;
        this.data.dest   = raw.dest;
        this.data.vaddr  = raw.vaddr;
        this.data.len    = raw.len;
        this.data.last   = raw.last;
    endfunction
endclass

class trs_ctrl;
    typedef struct packed {
        longint data;
        longint addr;
    } set_binary_format_t; // Values are the other way around in the binary format because they are serialized like this

    typedef struct packed {
        byte    do_polling;
        longint data;
        longint addr;
    } get_binary_format_t; // Values are the other way around in the binary format because they are serialized like this

    static int SET_BYTES = $bits(set_binary_format_t) / 8;
    static int GET_BYTES = $bits(get_binary_format_t) / 8;

    logic is_write;
    logic[AXI_ADDR_BITS  - 1:0] addr;
    logic[AXIL_DATA_BITS - 1:0] data;
    logic do_polling;

    function new();
        this.is_write = 0;
        this.addr = 0;
        this.data = 0;
        this.do_polling = 0;
    endfunction

    function void initializeSet(input logic[511:0] data);
        set_binary_format_t raw = data[$bits(set_binary_format_t) - 1:0];

        this.is_write = 1;
        this.addr = raw.addr;
        this.data = raw.data;
        this.do_polling = 0;
    endfunction

    function void initializeGet(input logic[511:0] data);
        get_binary_format_t raw = data[$bits(get_binary_format_t) - 1:0];

        this.is_write = 0;
        this.addr = raw.addr;
        this.data = raw.data;
        this.do_polling = raw.do_polling;
    endfunction
endclass

class c_trs_ack;
    bit rd;
    logic [4:0] opcode;
    logic [1:0] strm;
    logic remote;
    logic host;
    logic [3:0] dest;
    logic [5:0] pid;
    logic [3:0] vfid;
    logic last;

    function new();
        this.rd     = 0;
        this.opcode = 0;
        this.strm   = 0;
        this.remote = 0;
        this.host   = 0;
        this.dest   = 0;
        this.pid    = 0;
        this.vfid   = 0;
        this.last   = 0;
    endfunction

    function void initialize(input bit rd, c_trs_req req);
        this.rd     = rd;
        this.opcode = req.data.opcode;
        this.strm   = req.data.strm;
        this.remote = req.data.remote;
        this.host   = req.data.host;
        this.dest   = req.data.dest;
        this.pid    = req.data.pid;
        this.vfid   = req.data.vfid;
        this.last   = req.data.last;
    endfunction
endclass
