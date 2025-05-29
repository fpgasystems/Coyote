import lynxTypes::*;

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

    function initialize(input bit rd, c_trs_req req);
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
