import lynxTypes::*;

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

    function new(input bit rd, input logic [4:0] opcode, input logic [1:0] strm, input logic remote, input logic host, input logic [3:0] dest, input logic [5:0] pid, input logic [3:0] vfid, input logic last);
        this.rd = rd;
        this.opcode = opcode;
        this.strm = strm;
        this.remote = remote;
        this.host = host;
        this.dest = dest;
        this.pid = pid;
        this.vfid = vfid;
        this.last = last;
    endfunction
endclass

class c_trs_notify;
    bit[37:0] data;

    function new();
        data = 38'd0;
    endfunction
endclass

class c_trs_req;
    req_t data;
    realtime req_time;

    function new();
        data = 0;
        req_time = $realtime;
    endfunction
endclass
