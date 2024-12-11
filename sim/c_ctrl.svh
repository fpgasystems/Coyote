import lynxTypes::*;
import simTypes::*;


// AXI4L driver
class c_drv_ctrl;
	
	// Interface handle
	virtual AXI4L axi_ctrl;
	
	// Mailbox handle
	mailbox gen2ctrl;
	// mailbox drv2scb; something like this should probably happen

	// Number of transactions
	int n_trs;
	
	event done;
	
	// 
	// C-tor
	//
	function new(virtual AXI4L axi, mailbox gen2ctrl);
		this.axi_ctrl = axi;
		this.gen2ctrl = gen2ctrl;
		//this.drv2scb = drv2scb;
	endfunction
  
	// Reset
	task reset_m;
		axi_ctrl.araddr <= 0;
		axi_ctrl.arprot <= 0;
		axi_ctrl.arqos <= 0;
		axi_ctrl.arregion <= 0;
		axi_ctrl.arvalid <= 0;
		axi_ctrl.awaddr <= 0;
		axi_ctrl.awprot <= 0;
		axi_ctrl.awqos <= 0;
		axi_ctrl.awregion <= 0;
		axi_ctrl.awvalid <= 0;
		axi_ctrl.bready <= 0;
		axi_ctrl.rready <= 0;
		axi_ctrl.wdata <= 0;
		axi_ctrl.wstrb <= 0;
		axi_ctrl.wvalid <= 0;
		$display("AXIL reset_m() completed.");
	endtask
  
	//
	// Run
	//
	task run;
		forever begin
		c_trs_ctrl trs;
		gen2ctrl.get(trs);
		//drv2scb.put(trs); // TODO: again, this should probably happen
		
		if (trs.done_signal) -> done;
		
		if (trs.read) begin
			// Request
			axi_ctrl.araddr		<= trs.addr;
			axi_ctrl.arvalid	<= 1'b1;

			while (axi_ctrl.arready != 1'b1) begin #1; end

        	axi_ctrl.araddr		<= 0;
        	axi_ctrl.arvalid	<= 1'b0;
			// Response
        	axi_ctrl.rready  <= 1'b1;

			while(axi_ctrl.rvalid != 1) begin #1; end

			axi_ctrl.rready  <= 1'b0;
			$display("AXIL read() completed. Data: %x, addr: %x", axi_ctrl.rdata, trs.addr);
		end
		else begin
			// Request
			axi_ctrl.awaddr  <= trs.addr;
			axi_ctrl.awvalid <= 1'b1;
			axi_ctrl.wdata   <= trs.data;
			axi_ctrl.wstrb   <= ~0;
			axi_ctrl.wvalid  <= 1'b1;

			while(axi_ctrl.awready != 1'b1 && axi_ctrl.wready != 1'b1) begin #1; end

			axi_ctrl.awaddr  <= 0;
			axi_ctrl.awvalid <= 1'b0;
			axi_ctrl.wdata   <= 0;
			axi_ctrl.wstrb   <= 0;
			axi_ctrl.wvalid  <= 1'b0;
			// Response
			axi_ctrl.bready  <= 1'b1;

			while(axi_ctrl.bvalid != 1) begin #1; end

			axi_ctrl.bready  <= 1'b0;
			$display("AXIL write() completed. Data: %x, addr: %x", trs.data, trs.addr);
		end
	
		
		trs.display("Drv");
		n_trs++;
		end
	endtask
  
endclass


class c_ctrl;
	
	
	c_gen_ctrl gen;
	c_drv_ctrl drv;
	
    mailbox gen2ctrl;
	
    virtual AXI4L axi_ctrl;
	
	event done;
	
    function new(virtual AXI4L axi, input c_struct_t params);
		// Interface
        this.axi_ctrl = axi;
		
		// Mailbox
		gen2ctrl = new();
		
		// Env
		this.gen = new(gen2ctrl, params);
		this.drv = new(axi, gen2ctrl);
    endfunction
	
	task reset;
		drv.reset_m();
	endtask
	
	// implemented by me
	task env_threads();
		fork
			gen.run();
			drv.run();
			//mon.run();
			//scb.run();
		join_any
	endtask
	
    task env_done();
        wait(gen.done.triggered);
		wait(drv.done.triggered);
        //wait(scb.done.triggered);
    endtask
	
	
    task run;
        reset();
        env_threads();
        env_done();
        /*if(scb.fail == 0) begin 
            $display("Stream run completed, type: %d", strm_type);
        end
        else begin
            $display("Stream run failed, type: %d", strm_type);
        end*/
        -> done;
    endtask
	
endclass