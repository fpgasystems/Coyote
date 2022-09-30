import lynxTypes::*;
import simTypes::*;

class c_trs;

  // AXIS
  rand bit [AXI_DATA_BITS-1:0]    tdata;
       bit                        tlast;
       bit [PID_BITS-1:0]         tid;

  function void display(input string id);
    $display("U: %s, data: %x, id: %d,last: %d", id, tdata, tid, tlast);
  endfunction
  
endclass