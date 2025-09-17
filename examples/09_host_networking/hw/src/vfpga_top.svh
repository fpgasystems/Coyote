// vFPGA for host networking -> Outgoing traffic is just directly channelled through towards the CMAC, incoming traffic needs to be buffered to generate a DMA command 
/*
 * vFPGA for host networking 
 * -> Outgoing traffic is just directly channelled through towards the CMAC
 * -> Incoming traffic needs to be buffered to generate a DMA command 
 * -> The specifics of the DMA command (vaddr, pid) need to be set by the user via the axi_ctrl interface 
 */ 

 // BUILD-VERSION, stable for now. 

/*
 * AXI CTRL parsing 
 */ 

 // Virtual base address for host networking buffer (RX buffers)
logic [VADDR_BITS-1:0] host_networking_buff_vaddr;

// Stride of the single buffer fields in the host networking buffer ring
logic [VADDR_BITS-1:0] host_networking_buff_stride;

// Size of the host networking buffer ring (in number of entries)
logic [VADDR_BITS-1:0] host_networking_ring_size;

// Virtual base address for host networking meta information (RX meta)
logic [VADDR_BITS-1:0] host_networking_meta_vaddr;

// Stride of the single meta fields in the host networking meta ring
logic [VADDR_BITS-1:0] host_networking_meta_stride;

// Tail pointer of the host networking buffer ring (updated by software)
logic [VADDR_BITS-1:0] host_networking_ring_tail;

// Head pointer of the host networking buffer ring (updated by hardware)
logic [VADDR_BITS-1:0] host_networking_ring_head;

// IRQ coalescing timer (in number of clock cycles or received packets, to be defined)
logic [31:0] host_networking_irq_coalesce;

// Coyote thread ID (obtained in software from coyote_thread.getCtid())
logic [PID_BITS-1:0] host_networking_pid;

// Define a packet counter for keeping track of the descriptors and required buffers
logic [VADDR_BITS-1:0] packet_counter;

host_networking_axi_ctrl_parser inst_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .host_networking_pid(host_networking_pid),
    .host_rx_buff_addr(host_networking_buff_vaddr), 
    .host_rx_buff_stride(host_networking_buff_stride), 
    .host_rx_ring_size(host_networking_ring_size), 
    .host_rx_meta_addr(host_networking_meta_vaddr), 
    .host_rx_meta_stride(host_networking_meta_stride),
    .host_rx_ring_tail(host_networking_ring_tail), 
    .host_rx_ring_head(host_networking_ring_head)
    .host_rx_irq_coalesce(host_networking_irq_coalesce)
);

/*
 * TX Traffic  
 */ 
`AXISR_ASSIGN(axis_host_recv[0], axis_host_networking_tx)

/* 
 * RX Traffic
 * -> Incoming streams are buffered in a DATA-FIFO to count their lenght and generate a DMA command 
 * -> Measured length is stored in a second META-FIFO that connects to the release FSM
 * -> Only after generating the DMA Command, the META-FIFO is updated to start the release process in a second FSM 
 */ 

 // Variable for the length of the incoming data stream 
logic [31:0] host_networking_len;

// Variable for the length of a release process of a stream 
logic [31:0] release_len;
logic [31:0] current_release_len;

// Function for tkeep popcount to get the length of a chunk as part of the DMA command length 
function[31:0] get_chunk_length_in_bytes;
    input logic [63:0] tkeep;
    integer i;
    begin 
        get_chunk_length_in_bytes = 0;
        for(i=0; i<64; i=i+1) begin 
            if(tkeep[i]) begin 
                get_chunk_length_in_bytes = get_chunk_length_in_bytes + 1;
            end
        end
    end
endfunction

// Definition of the states for the FSM for buffering incoming data streams 
typedef enum logic [3:0] {
    RECEIVE_IDLE = 0, 
    RECEIVE_STREAM = 1, 
    SEND_DMA_CMD_DATA_STREAM = 2, 
    SEND_DMA_CMD_WAIT = 3, 
    SEND_DMA_CMD_META_STREAM = 4
} ReceptionFSMState;

// Definition of the states for the FSM for releasing buffered data streams 
typedef enum logic [3:0] {
    RELEASE_IDLE = 0, 
    RELEASE_CHUNK = 1
} ReleaseFSMState;

// Definition of the state variables for the FSMs
ReceptionFSMState reception_state;
ReleaseFSMState release_state;

// Initialization of the DATA FIFO for buffering incoming data streams 

logic release_data_ready; // Signal for the release FSM to control the release process of packets onto the wire 
logic release_data_ready_combined_signal; 
assign release_data_ready_combined_signal = release_data_ready & axis_host_send[0].tready;

// Signal for tvalid of the outgoing data stream 
logic axis_host_send_tvalid; 
assign axis_host_send[0].tvalid = axis_host_send_tvalid & release_data_ready_combined_signal & (host_networking_buff_vaddr != 0);

axis_data_fifo_512_dma_cmd inst_axis_data_fifo_512_dma_cmd(
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(axis_host_networking_rx.tvalid),
    .s_axis_tready(axis_host_networking_rx.tready),
    .s_axis_tdata(axis_host_networking_rx.tdata),
    .s_axis_tkeep(axis_host_networking_rx.tkeep),
    .s_axis_tlast(axis_host_networking_rx.tlast),
    //.m_axis_aclk(rclk),
    .m_axis_tvalid(axis_host_send_tvalid),
    .m_axis_tready(release_data_ready_combined_signal),
    .m_axis_tdata(axis_host_send[0].tdata),
    .m_axis_tkeep(axis_host_send[0].tkeep),
    .m_axis_tlast(axis_host_send[0].tlast)
); 

// Initialization of the META FIFO for the release process with the DMA lengths 

logic submit_dma_length_valid; // Signal to submit the DMA length to the FIFO for the release process 
logic submit_dma_length_ready; 
logic release_dma_length_valid; // Signal to release the DMA length from the FIFO for the release process  
logic release_dma_length_ready; 

logic [3:0] submit_dma_length_keep; 
logic submit_dma_length_last; 

assign submit_dma_length_keep = 4'b1111; 
assign submit_dma_length_last = 1'b1;

logic [3:0] release_dma_length_keep; 
logic release_dma_length_last;

axis_meta_fifo_32 inst_axis_meta_fifo_32(
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),
    .s_axis_tvalid(submit_dma_length_valid),
    .s_axis_tready(submit_dma_length_ready),
    .s_axis_tdata(host_networking_len),
    .s_axis_tkeep(submit_dma_length_keep), 
    .s_axis_tlast(submit_dma_length_last),
    .m_axis_tvalid(release_dma_length_valid),
    .m_axis_tready(release_dma_length_ready),
    .m_axis_tdata(release_len), 
    .m_axis_tkeep(release_dma_length_keep),
    .m_axis_tlast(release_dma_length_last)
);

// Reception FSM to buffer all incoming data streams 

// Signal for alternative sending of DMA command for meta information
logic send_dma_meta_command_valid; 
logic [511:0] send_dma_meta_command_data;
logic [63:0]  send_dma_meta_command_keep;

// Ring access counter that is maintained for correct access of the ring buffers
always @ (posedge aclk) begin 
    if(!aresetn) begin 
        reception_state <= RECEIVE_IDLE; 
        host_networking_len <= 0; 
        submit_dma_length_valid <= 0; 
        send_dma_meta_command_valid <= 0;
        host_networking_ring_tail <= 0; 
    end else begin 
        case(reception_state)

            RECEIVE_IDLE: begin 
                // Reset the submit signal for the DMA length to the META-FIFO
                submit_dma_length_valid <= 0;

                // Wait for an incoming stream chunk that is received and buffered in the DATA-FIFO 
                if(axis_host_networking_rx.tvalid && axis_host_networking_rx.tready && (host_networking_vaddr != 0)) begin 
                    // Update the DMA-length for the current chunk 
                    host_networking_len <= $countones(axis_host_networking_rx.tkeep)*8;

                    // Move to the next state dependent on the tlast signal of the stream transmission: 
                    // -> If tlast is set, the stream is finished and the DMA command can be sent
                    // -> If tlast is not set, the stream is still ongoing and the DMA command cannot be sent yet
                    if(axis_host_networking_rx.tlast) begin 
                        reception_state <= SEND_DMA_CMD_DATA_STREAM; 
                    end else begin 
                        reception_state <= RECEIVE_STREAM; 
                    end
                end
            end 

            RECEIVE_STREAM: begin 
                // Wait for an incoming stream chunk that is received and buffered in the DATA-FIFO
                if(axis_host_networking_rx.tvalid && axis_host_networking_rx.tready) begin 
                    // Update the DMA-length for the current chunk 
                    host_networking_len <= host_networking_len + ($countones(axis_host_networking_rx.tkeep)*8);

                    // Move on based on the tlast signal of the stream transmission
                    if(axis_host_networking_rx.tlast) begin 
                        reception_state <= SEND_DMA_CMD_DATA_STREAM; 
                    end else begin 
                        reception_state <= RECEIVE_STREAM; 
                    end
                end 
            end 

            SEND_DMA_CMD_DATA_STREAM: begin 
                // Only leave this state if the DMA command has been sent (as signaled by the tready signal of the DMA-command)
                if(sq_wr.ready && submit_dma_length_ready) begin 
                    // Move back to the IDLE state to wait for the next incoming stream chunk 
                    reception_state <= SEND_DMA_CMD_WAIT; 

                    // Submit the length of the stream to the META-FIFO for the release process
                    submit_dma_length_valid = 1'b1;
                end 
            end

            SEND_DMA_CMD_WAIT: begin
                // Reset the submit signal for the DMA length to the META-FIFO
                submit_dma_length_valid <= 0;

                // Only send the DMA meta command after the data stream for the actual packet has been sent 
                if(axis_host_send_tvalid && axis_host_send[0].tlast && release_data_ready_combined_signal) begin 
                    reception_state <= SEND_DMA_CMD_META_STREAM; 
                    send_dma_meta_command_valid <= 1'b1;
                end
            end

            SEND_DMA_CMD_META_STREAM: begin 
                // Send the descriptor for the meta information - only leave this state if the DMA command has been sent (as signaled by the tready signal of the DMA-command)
                if(sq_wr.ready) begin 
                    // Reset the dma command valid signal for the meta information
                    send_dma_meta_command_valid <= 1'b0;
                    reception_state <= RECEIVE_IDLE;

                    // Control the second DMA-transmission to send the meta information 
                    send_dma_meta_command_data[0] <= 1'b1; // In possession of the FPGA 
                    send_dma_meta_command_data[VADDR_BITS:1] <= host_networking_buff_vaddr + (host_networking_ring_tail * host_networking_buff_stride);
                    send_dma_meta_command_data[511:VADDR_BITS+1] <= 0; // Upper bits of vaddr not used

                    for(int i=0; i<64; i=i+1) begin 
                        send_dma_meta_command_keep[i] <= (i*64 < host_networking_meta_stride) ? 1'b1 : 1'b0;
                    end

                    // Count up the ring tail pointer after sending both DMA commands. Don't care about head pointer for now
                    if(host_networking_ring_tail == (host_networking_ring_size - 1)) begin 
                        host_networking_ring_tail <= 0; 
                    end else begin 
                        host_networking_ring_tail <= host_networking_ring_tail + 1;
                    end 
                end 
            end
            
              

        endcase 
    end 
end 


// Release FSM to release the buffered data streams 
always @ (posedge aclk) begin 
    if(!aresetn) begin 
        release_state <= RELEASE_IDLE; 
        release_data_ready <= 0;
        current_release_len <= 0;
        release_dma_length_ready <= 0;	
    end else begin 
        case(release_state)

            RELEASE_IDLE: begin 
                // Wait for an entry in the META-FIFO to release the data stream
                if(release_dma_length_valid && (host_networking_vaddr != 0)) begin 
                    // Move to the next state to release the data stream
                    release_state <= RELEASE_CHUNK; 

                    // Release the length of the stream from the META-FIFO
                    current_release_len <= release_len; 

                    // Set the signal for releasing the data stream
                    release_data_ready <= 1'b1; 

                    // Set the signal for releasing the meta-FIFO
                    release_dma_length_ready <= 1'b1;
                end
            end 

            RELEASE_CHUNK: begin 
                // Reset the release signal for the meta-FIFO
                release_dma_length_ready <= 0;

                // Now check if the data stream is actually released (by checking if the accepting stream is ready)
                if(release_data_ready_combined_signal && axis_host_send_tvalid) begin 
                    // Check if the length of the stream is finished
                    if(current_release_len == 0) begin 
                        // Move back to the IDLE state to wait for the next incoming stream chunk 
                        release_state <= RELEASE_IDLE; 

                        // Reset the signal for releasing the data stream
                        release_data_ready <= 0; 
                    end else begin 
                        // Decrease the length of the stream by the length of the released chunk
                        current_release_len <= current_release_len - ($countones(axis_host_send[0].tkeep)*8); 
                    end
                end
            end 

        endcase
    end 
end 


// Create the final write request 
assign sq_wr.data.last = 1'b1; 
assign sq_wr.data.pid = host_networking_pid;
assign sq_wr.data.vaddr = host_networking_vaddr;
assign sq_wr.data.len = host_networking_len[27:0]; // The upper four bits are just used for padding in the META-FIFO
assign sq_wr.data.strm = STRM_HOST;
assign sq_wr.data.opcode = LOCAL_WRITE;
assign sq_wr.data.mode = 0; // Not used
assign sq_wr.data.rdma = 1'b0;
assign sq_wr.data.vfid = 6'b0;
assign sq_wr.data.actv = 1'b1;
assign sq_wr.data.host = 1'b1;
assign sq_wr.data.offs = 0;
assign sq_wr.data.rsrvd = 0;

always_comb begin 
    // Some of the command fields depend on the current state of the reception FSM 
    if(reception_state == SEND_DMA_CMD_DATA_STREAM) begin 
        sq_wr.data.vaddr = host_networking_buff_vaddr + (host_networking_ring_tail * host_networking_buff_stride);
        sq_wr.data.len = host_networking_len[27:0]; // The upper four bits are just used for padding in the META-FIFO
    end else if(reception_state == SEND_DMA_CMD_WAIT) begin 
        sq_wr.data.vaddr = host_networking_meta_vaddr + (host_networking_ring_tail * host_networking_meta_stride);
        sq_wr.data.len = host_rx_meta_stride; // Fixed length of meta information
    end else begin 
        sq_wr.data.vaddr = 0;
        sq_wr.data.len = 0;
    end 
end 

assign sq_wr.valid = (reception_state == SEND_DMA_CMD_DATA_STREAM) && (host_networking_vaddr != 0); 


/*
 * Tie-off of unused signals 
 */ 

always_comb notify.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();
always_comb sq_rd.tie_off_m();
always_comb axis_host_send[1].tie_off_m();
always_comb axis_host_recv[1].tie_off_s();

// Since we co-configure RDMA, we also need to tie off the unused interfaces of the RDMA-stack 
always_comb axis_rreq_send[0].tie_off_m(); 
always_comb axis_rreq_recv[0].tie_off_s();
always_comb axis_rrsp_send[0].tie_off_m();
always_comb axis_rrsp_recv[0].tie_off_s();


/*
 * ILA for debugging 
 */
ila_host_networking inst_ila_host_networking (
    .clk(aclk), 

    // TX-Path 
    .probe0(axis_host_networking_tx.tvalid),      // 1
    .probe1(axis_host_networking_tx.tready),      // 1
    .probe2(axis_host_networking_tx.tlast),       // 1
    .probe3(axis_host_networking_tx.tdata),       // 512
    .probe4(axis_host_networking_tx.tkeep),       // 64

    // RX-Path
    .probe5(axis_host_networking_rx.tvalid),      // 1
    .probe6(axis_host_networking_rx.tready),      // 1
    .probe7(axis_host_networking_rx.tlast),       // 1
    .probe8(axis_host_networking_rx.tdata),       // 512
    .probe9(axis_host_networking_rx.tkeep),       // 64
    .probe10(axis_host_send[0].tvalid),              // 1
    .probe11(axis_host_send[0].tready),              // 1
    .probe12(axis_host_send[0].tlast),               // 1
    .probe13(axis_host_send[0].tdata),               // 512
    .probe14(axis_host_send[0].tkeep),               // 64

    // DMA-Command
    .probe15(sq_wr.valid),                        // 1
    .probe16(sq_wr.ready),                        // 1
    .probe17(sq_wr.data),                         // 128

    // Control signals 
    .probe18(reception_state),                    // 4
    .probe19(release_state),                     // 4
    .probe20(host_networking_len),                // 32
    .probe21(release_len),                        // 32
    .probe22(current_release_len),                // 32
    .probe23(host_networking_vaddr),             // 48
    .probe24(host_networking_pid),               // 6
    .probe25(release_data_ready),                // 1
    .probe26(submit_dma_length_valid),           // 1
    .probe27(submit_dma_length_ready),           // 1
    .probe28(release_dma_length_valid),          // 1
    .probe29(release_data_ready_combined_signal), // 1
    .probe30(axis_host_send_tvalid)               // 1
); 