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

    function new(input bit _rd, input logic [4:0] _opcode, input logic [1:0] _strm, input logic _remote, input logic _host, input logic [3:0] _dest, input logic [5:0] _pid, input logic [3:0] _vfid);
        rd = _rd;
        opcode = _opcode;
        strm = _strm;
        remote = _remote;
        host = _host;
        dest = _dest;
        pid = _pid;
        vfid = _vfid;
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
