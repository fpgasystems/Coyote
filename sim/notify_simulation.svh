

class notify_simulation;
	
	c_meta #(.ST(irq_not_t)) notify;
	
	event done;
	int notify_output_file;
	
	function new(c_meta #(.ST(irq_not_t)) notify_drv);
		notify = notify_drv;
	endfunction
	
	task initialize(string path_name);
		notify.reset_s();
		notify_output_file = $fopen({path_name, "notify_output.txt"}, "w");
	endtask
	
	task run();
		irq_not_t trs; // TODO: needs to be a class wrapping this type

		forever begin
			notify.recv(trs); // TODO: adapt driver to return a value here
			$fdisplay(notify_output_file, "Notify PID: %x, value: %x", trs.pid, trs.value);
			
		end
	endtask
	
endclass