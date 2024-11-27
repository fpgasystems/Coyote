/**
 * VFPGA TOP FOR DPI 
 *
 * Catch write commands to check if an IRQ needs to be raised or not
 *
 */ 

// Direct comb of the read-interface, we're only looking at the write-commands for IRQs 
always_comb begin 
    // Read ops 
    sq_rd.valid = rq_rd.valid;
    rq_rd.ready = sq_rd.ready;
    sq_rd.data = rq_rd.data;
    // OW
    sq_rd.data.strm = STRM_HOST;
    sq_rd.data.dest = 1;
end 

// Introduce additional pipeline stage that allows to modify the write commands if it's actually malicious 
req_t sq_wr_data_intermediate; 
logic sq_wr_valid_intermediate; 

irq_not_t notify_data_intermediate; 
logic notify_valid_intermediate; 

logic interrupt_raised; 

// Do the required assignments to the intermediate pipeline-stage
assign sq_wr.valid = sq_wr_valid_intermediate; 
assign sq_wr.data = sq_wr_data_intermediate;
assign rq_rd.ready = sq_wr.ready; 

assign notify.valid = notify_valid_intermediate; 
assign notify.data = notify_data_intermediate; 

// Synchronous block to catch incoming commands and generate IRQs if required 
always_ff @(posedge aclk) begin 
    if(!aresetn) begin
        // Reset all intermediate registers 
        sq_wr_data_intermediate <= 512'b0; 
        sq_wr_valid_intermediate <= 1'b0;  

        notify_valid_intermediate <= 1'b0; 
        notify_data_intermediate <= 38'b0; 

        // Reset the interrupt-raised register 
        interrupt_raised <= 1'b0; 
    end else begin
        // Wait for incoming command
        if(rq_wr.valid && sq_wr.ready) begin
            // Check the opcode of this command 
            if(rq_wr.data.opcode == RC_ROCE_DPI_IRQ) begin 
                // If the incoming command-opcode is the specialized DPI_IRQ, stop the transmission of the command and raise an actual interrupt 
                sq_wr_data_intermediate <= 512'b0; 
                sq_wr_valid_intermediate <= 1'b0; 

                // For the interrupt, forward the pid from the incoming command 
                notify_valid_intermediate <= 1'b1;
                notify_data_intermediate.pid <= rq_wr.data.pid; 
                notify_data_intermediate.value <= IRQ_DPI; 

                // Set the bit that indicates that the interrupt was written 
                interrupt_raised <= 1; 
            end else begin 

            end 
        end else begin 
            // If there's no command coming in, just reset the intermediate command stage 
            sq_wr_data_intermediate <= 512'b0; 
            sq_wr_valid_intermediate <= 1'b0; 
        end 

        // Check if interrupt was raised and picked up (ready-signal!) If so, it can be deasserted. 
        if(interrupt_raised && notify.ready) begin 
            interrupt_raised <= 1'b0; 
            notify_data_intermediate <= 38'b0; 
            notify_valid_intermediate <= 1'b0; 
        end 
    end 
end 

`AXISR_ASSIGN(axis_host_recv[0], axis_rreq_send[0])
`AXISR_ASSIGN(axis_rreq_recv[0], axis_host_send[0])
`AXISR_ASSIGN(axis_host_recv[1], axis_rrsp_send[0])
`AXISR_ASSIGN(axis_rrsp_recv[0], axis_host_send[1])

ila_0 inst_ila (
    .clk(aclk),
    .probe0(axis_host_recv[0].tvalid),
    .probe1(axis_host_recv[0].tready),
    .probe2(axis_host_recv[0].tlast),

    .probe3(axis_host_recv[1].tvalid),
    .probe4(axis_host_recv[1].tready),
    .probe5(axis_host_recv[1].tlast),

    .probe6(axis_host_send[0].tvalid),
    .probe7(axis_host_send[0].tready),
    .probe8(axis_host_send[0].tlast),

    .probe9(axis_host_send[1].tvalid),
    .probe10(axis_host_send[1].tready),
    .probe11(axis_host_send[1].tlast),

    .probe12(sq_wr.valid),
    .probe13(sq_wr.ready),
    .probe14(sq_wr.data), // 128
    .probe15(sq_rd.valid),
    .probe16(sq_rd.ready),
    .probe17(sq_rd.data), // 128
    .probe18(cq_rd.valid),
    .probe19(cq_wr.valid)
);

// Tie-off unused 
always_comb axi_ctrl.tie_off_s();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();