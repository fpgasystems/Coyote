`include "log.svh"
`include "scoreboard.svh"

class notify_simulation;
	c_meta #(.ST(irq_not_t)) drv;
	scoreboard scb;
	
	function new(c_meta #(.ST(irq_not_t)) notify_drv, scoreboard scb);
		this.drv = notify_drv;
		this.scb = scb;
	endfunction
	
	task initialize();
		drv.reset_s();
	endtask
	
	task run();
		irq_not_t trs;

		forever begin
			drv.recv(trs);
			scb.writeNotify(trs);
			`DEBUG(("PID: %x, value: %x", $realtime, trs.pid, trs.value))
		end
	endtask
endclass