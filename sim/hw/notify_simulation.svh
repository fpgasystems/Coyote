

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
		irq_not_t trs;

		forever begin
			notify.recv(trs);
			$fdisplay(notify_output_file, "%t: Notify PID: %x, value: %x", $realtime, trs.pid, trs.value);
		end
	endtask

	task close();
		$fclose(notify_output_file);
	endtask
	
endclass