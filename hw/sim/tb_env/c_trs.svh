class c_trs;

  // AXIS
  rand bit [AXI_DATA_BITS-1:0]    tdata;
       bit                        tlast;

  function void display(input string id);
    $display("U: %s, data: %x, last: %d", id, tdata, tlast);
  endfunction
  
endclass