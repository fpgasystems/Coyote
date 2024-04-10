class c_trs;

  // AXIS
  rand bit [AXI_DATA_BITS-1:0]    tdata;
       bit                        tlast;
       bit [AXI_ID_BITS-1:0]      tid;

  function void display(input string id);
    $display("U: %s, data: %x, last: %d, id: %d", id, tdata, tlast, tid);
  endfunction
  
endclass