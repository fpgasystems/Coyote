import lynxTypes::*;

class c_trs;

  // AXIS
  rand bit [AXI_DATA_BITS-1:0]    tdata;
       bit                        tlast;
       bit [PID_BITS-1:0]         tid;

  function void display(input string id);
    $display("U: %s, data: %x, id: %d,last: %d", id, tdata, tid, tlast);
  endfunction
  
endclass


class c_trs_ctrl;

    // AXIL
    bit done_signal;
    bit read;
    bit [AXI_ADDR_BITS-1:0]    addr;
    bit [AXIL_DATA_BITS-1:0]    data;

    function void display(input string id);
        $display("U: %s, read: %d, addr: %x, read: %x", id, read, addr, data);
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

class c_trs_strm_data;

    bit[511:0] data;
    bit[63:0] keep;
    bit last;
    bit[5:0] pid;

    function new();
        data = 512'd0;
        keep = 64'd0;
        last = 0;
        pid = 0;
    endfunction

endclass