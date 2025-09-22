// VFPGA FOR HOST NETWORKING, ALTERNATIVE VERSION -> RECEIVE INTO FIFOs, RELEASE CENTRALLY & MERGED


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 1: AXI-CTRL PARSING 
//
////////////////////////////////////////////////////////////////////////////////

// ----------------------------------------------------------------------------
// Definition of all the communication interfaces to the control parser 
// ----------------------------------------------------------------------------

// Base address of the packet buffers 
logic [VADDR_BITS-1:0] host_networking_buff_vaddr;

// Stride of every single buffer in the contiguous ring 
logic [VADDR_BITS-1:0] host_networking_buff_stride;

// Size of the packet buffer ring 
logic [VADDR_BITS-1:0] host_networking_ring_size;

// Head and tail pointers of the packet buffer ring 
logic [VADDR_BITS-1:0] host_networking_ring_head;
logic [VADDR_BITS-1:0] host_networking_ring_tail;

// IRQ coalescing packet counter 
logic [31:0] host_networking_irq_coalesce;

// Coyote thread ID to be used for the local writes 
logic [15:0] host_networking_pid;

// ----------------------------------------------------------------------------
// Instantiation of the control parser
// ----------------------------------------------------------------------------

host_networking_axi_ctrl_parser inst_axi_ctrl_parser (
    .aclk(aclk),
    .aresetn(aresetn),
    .axi_ctrl(axi_ctrl),
    .host_networking_pid(host_networking_pid),
    .host_networking_buff_addr(host_networking_buff_vaddr), 
    .host_networking_buff_stride(host_networking_buff_stride), 
    .host_networking_ring_size(host_networking_ring_size), 
    .host_networking_ring_tail(host_networking_ring_tail), 
    .host_networking_ring_head(host_networking_ring_head),
    .host_networking_irq_coalesce(host_networking_irq_coalesce)
);


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 2: Definition of the FIFOs for the data stream and meta tags 
//
////////////////////////////////////////////////////////////////////////////////

// ----------------------------------------------------------------------------
// FIFO for the data stream
// ----------------------------------------------------------------------------

// Valid out signal for the data stream
logic data_stream_valid_out;

// Data out signal for the data stream
logic [511:0] data_stream_data_out;

// Keep out signal for the data stream
logic [63:0] data_stream_keep_out;

// Ready in signal for the data stream
logic data_stream_ready_in;

// Last out signal for the data stream
logic data_stream_last_out;

// Additional ready signal to be able to tie connection to successful control setup 
logic data_stream_fifo_reception_ready; 
logic data_stream_fifo_reception_valid; 

// Instantiation of the FIFO for the data stream
axis_data_fifo_512_dma_cmd inst_axis_data_fifo_512_dma_cmd(
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),

    // Signals in -> From the host networking interface 
    .s_axis_tvalid(data_stream_fifo_reception_valid),
    .s_axis_tready(data_stream_fifo_reception_ready),
    .s_axis_tdata(axis_host_networking_rx.tdata),
    .s_axis_tkeep(axis_host_networking_rx.tkeep),
    .s_axis_tlast(axis_host_networking_rx.tlast),

    // Signals out -> Towards the release FSM with the merger of Meta-Tag and Data Stream
    .m_axis_tvalid(data_stream_valid_out),
    .m_axis_tready(data_stream_ready_in),
    .m_axis_tdata(data_stream_data_out),
    .m_axis_tkeep(data_stream_keep_out),
    .m_axis_tlast(data_stream_last_out)
); 

// Connect the ready signal of the incoming host networking to the control setup and the FIFO reception
assign axis_host_networking_rx.tready = data_stream_fifo_reception_ready && reception_fsm_ready;
assign data_stream_fifo_reception_valid = axis_host_networking_rx.tvalid && (host_networking_buff_vaddr != 0);


// ----------------------------------------------------------------------------
// FIFO for the meta tags
// ----------------------------------------------------------------------------

// Definition of a meta tag structure in 32 bit to fit within a 32 bit wide FIFO
typedef struct packed {
    logic possession_flag;       // 1 bit -> Indicates whether the buffer is in possession of the FPGA (1) or the Host (0)
    logic [27:0] packet_len;     // 28 bits -> Length of the packet received and allocated in the subsequent buffer 
    logic [2:0] rsvd;            // 3 bits -> Reserved for future use
} meta_tag_t; 

// Valid in signal for the meta tag stream
logic meta_tag_valid_in;

// Data in signal for the meta tag stream
meta_tag_t meta_tag_data_in;

// Ready out signal for the meta tag stream
logic meta_tag_ready_out;

// Valid out signal for the meta tag stream
logic meta_tag_valid_out;

// Data out signal for the meta tag stream
meta_tag_t meta_tag_data_out;

// Ready in signal for the meta tag stream
logic meta_tag_ready_in;

// Instantiation of the FIFO for the meta tags
axis_meta_fifo_32 inst_axis_meta_fifo_32(
    .s_axis_aresetn(aresetn),
    .s_axis_aclk(aclk),

    // Signals in -> Generated by the reception FSM of the data stream 
    .s_axis_tvalid(meta_tag_valid_in),
    .s_axis_tready(meta_tag_ready_out),
    .s_axis_tdata(meta_tag_data_in),
    .s_axis_tkeep(4'b1111),          // Keep is not used for the meta tags, so we set it to all ones
    .s_axis_tlast(1'b1),             // Last is not used for the

    // Signals out -> Towards the release FSM with the merger of Meta-Tag and Data Stream
    .m_axis_tvalid(meta_tag_valid_out),
    .m_axis_tready(meta_tag_ready_in),
    .m_axis_tdata(meta_tag_data_out),
    .m_axis_tkeep(),                 // Keep is not used for the meta tags, so leave the port empty 
    .m_axis_tlast()                  // Last is not used for the meta tags, so leave the port empty 
); 


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 3: Reception FSM to receive the data stream and generate meta tags
//
////////////////////////////////////////////////////////////////////////////////

// ----------------------------------------------------------------------------
// Definition of the states of the reception FSM
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {
    RECEIVE_IDLE = 0, 
    RECEIVE_STREAM_CHUNK = 1, 
    SUBMIT_META_TAG_TO_FIFO = 2, 
    WAIT_FOR_META_TAG_ACCEPTANCE = 3
} reception_state_t;

// ----------------------------------------------------------------------------
// Definition of the signals used in the reception FSM
// ----------------------------------------------------------------------------

// State variable for the reception FSM
reception_state_t reception_state;

// Signal to indicate that the reception FSM can accept a new data stream chunk
logic reception_fsm_ready;

// ----------------------------------------------------------------------------
// FF-logic for the FSM 
// ----------------------------------------------------------------------------

always_ff @(posedge aclk) begin 
    if(!aresetn) begin

        // Synchronous reset: Move to idle state, reset all the signals for the meta tag FIFO
        reception_state <= RECEIVE_IDLE;
        meta_tag_valid_in <= 1'b0;
        meta_tag_data_in <= 0;
        reception_fsm_ready <= 1'b1;    

    end else begin 

        // FSM: Case-conditional for the reception_state
        case(reception_state)

            // Idle state: Wait for a valid data stream to arrive (and successful control setup)
            RECEIVE_IDLE: begin 
                // Reset the signal for submission of a meta tag to the FIFO
                meta_tag_valid_in <= 1'b0;

                // We're in IDLE and ready to accept a new data stream
                reception_fsm_ready <= 1'b1;

                // Check for a valid data stream and successful control setup (factored into tready signal)
                if(data_stream_fifo_reception_valid && axis_host_networking_rx.tready) begin 

                    // Begin to set up the meta tag
                    meta_tag_data_in.possession_flag <= 1'b1; // FPGA takes possession of the buffer
                    meta_tag_data_in.packet_len <= $countones(axis_host_networking_rx.tkeep);         // Count up based on tkeep of the incoming data stream 

                    // Move to the next state based on whether the first data chunk is also the last one
                    if(axis_host_networking_rx.tlast) begin
                        reception_state <= SUBMIT_META_TAG_TO_FIFO; 

                        // We're no longer ready to accept a new data stream
                        reception_fsm_ready <= 1'b0;
                    end else begin 
                        reception_state <= RECEIVE_STREAM_CHUNK; 
                    end
                end
            end

            // State to receive subsequent chunks of the data stream until the last chunk is received
            RECEIVE_STREAM_CHUNK: begin
                // Check for a valid data stream 
                if(axis_host_networking_rx.tvalid && axis_host_networking_rx.tready) begin 

                    // Increment the packet length based on tkeep of the incoming data stream 
                    meta_tag_data_in.packet_len <= meta_tag_data_in.packet_len + $countones(axis_host_networking_rx.tkeep); 

                    // Move to the next state based on whether the current data chunk is also the last one
                    if(axis_host_networking_rx.tlast) begin
                        reception_state <= SUBMIT_META_TAG_TO_FIFO; 

                        // We're no longer ready to accept a new data stream
                        reception_fsm_ready <= 1'b0;
                    end else begin 
                        reception_state <= RECEIVE_STREAM_CHUNK; 
                    end 
                end
            end

            // State to submit the prepared meta tag to the meta tag FIFO 
            SUBMIT_META_TAG_TO_FIFO: begin 
                // Set the valid signal to submit the meta tag to the FIFO
                meta_tag_valid_in <= 1'b1;

                // Move to the next state to wait for acceptance of the meta tag by the FIFO
                reception_state <= WAIT_FOR_META_TAG_ACCEPTANCE; 
            end

            // State to wait for acceptance of the meta tag by the FIFO 
            WAIT_FOR_META_TAG_ACCEPTANCE: begin 
                // Check whether the FIFO has accepted the meta tag
                if(meta_tag_ready_out) begin 

                    // Reset the valid signal for submission of a meta tag to the FIFO
                    meta_tag_valid_in <= 1'b0;

                    // Move back to the idle state to wait for a new data stream
                    reception_state <= RECEIVE_IDLE; 

                    // We're ready to accept a new data stream
                    reception_fsm_ready <= 1'b1;
                end
            end
        endcase 
    end 
end


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 4: Release FSM to merge the data stream and meta tags and issue DMA commands
//
////////////////////////////////////////////////////////////////////////////////

// ----------------------------------------------------------------------------
// Definition of the states of the release FSM
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {
    RELEASE_IDLE = 0,
    WAIT_FOR_DMA_CMD_ACCEPTANCE = 1,
    TRANSMIT_FIRST_CHUNK = 2,
    TRANSMIT_NEXT_CHUNK = 3, 
    TRANSMIT_LAST_CHUNK = 4,
    WAIT_FINAL_TRANSMISSION = 5
} ReleaseFSMState;

// ----------------------------------------------------------------------------
// Definition of the signals used in the release FSM
// ----------------------------------------------------------------------------

// State variable for the release FSM
ReleaseFSMState release_state;

// Signal for kicking off the merge IP
logic merge_start;

// Signal for the meta tag remainder if merging 
logic [31:0] stream_remainder_data; 
logic [63:0] stream_remainder_keep; 

// ----------------------------------------------------------------------------
// FF-logic for the FSM
// ----------------------------------------------------------------------------

always_ff @(posedge aclk) begin 
    if(!aresetn) begin 

        // Synchronous reset: Move to idle state and don't start the merge IP
        merge_start <= 1'b0;
        release_state <= RELEASE_IDLE;

        // Reset the DMA command valid signal
        sq_wr.valid <= 1'b0;

        // Reset the stream remainder 
        stream_remainder_data <= 0; 
        stream_remainder_keep <= 0; 

        // Reset all the signals for the merged data stream
        axis_host_send[0].tvalid <= 1'b0;
        axis_host_send[0].tdata <= 0;
        axis_host_send[0].tkeep <= 0;
        axis_host_send[0].tlast <= 0;

        // Reset the ready signals for the FIFOs 
        data_stream_ready_in <= 1'b0;
        meta_tag_ready_in <= 1'b0;

    end else begin 

        // FSM: Case-conditional for the release_state
        case(release_state)

            // Idle state: Wait for either a valid data stream chunk or a valid meta tag 
            RELEASE_IDLE: begin 
                // Reset the ready signal for the meta tag FIFOs
                meta_tag_ready_in <= 1'b0;

                // Reset the stream remainder
                stream_remainder_data <= 0;
                stream_remainder_keep <= 0;

                // Reset the ready-signals for the FIFOs
                data_stream_ready_in <= 1'b0;
                meta_tag_ready_in <= 1'b0;

                // Start to operate if both data and meta tag are ready for sending DMA commands 
                if(data_stream_valid_out && meta_tag_valid_out) begin 
                    // Move to the send state to wait if the DMA-command is accepted by the XDMA engine 
                    release_state <= WAIT_FOR_DMA_CMD_ACCEPTANCE; 

                    // Trigger the transmission of the DMA command to the XDMA engine 
                    sq_wr.valid <= 1'b1;
                    
                    // Count up the current ring position to be able to address the correct buffer 
                    if(host_networking_ring_tail == (host_networking_ring_size - 1)) begin 
                        host_networking_ring_tail <= 0;
                    end else begin 
                        host_networking_ring_tail <= host_networking_ring_tail + 1;
                    end
                end
            end

            // State to wait for acceptance of the DMA command by the XDMA engine
            WAIT_FOR_DMA_CMD_ACCEPTANCE: begin
                if(sq_wr.ready) begin 
                    // Reset the DMA command valid signal 
                    sq_wr.valid <= 1'b0;

                    // Set the release signals for the DATA and the META-Fifo 
                    meta_tag_ready_in <= 1'b1; 
                    data_stream_ready_in <= 1'b1; 

                    // Go to the state where we can deal with the transmission of the first data chunk to the host 
                    release_state <= TRANSMIT_FIRST_CHUNK; 
                end 
            end

            // State for transmitting the first chunk after having set the release signal for the FIFO 
            TRANSMIT_FIRST_CHUNK: begin 
                // Stop release from the meta tag FIFO anyways, there is only one entry per merged packet
                meta_tag_ready_in <= 1'b0;

                // Setup the first merge step and check the fill level:
                if(data_stream_last_out) begin 
                    // What if the original data stream only consisted of one chunk?
                    if($countones(data_stream_keep_out) > 60) begin
                        // With the added meta-tag, this would exceed 64 bytes -> Need to split the data stream into two chunks 
                        axis_host_send[0].tdata [31:0] <= meta_tag_data_out; // First 32 bits are the meta tag
                        axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                        axis_host_send[0].tkeep <= 64'hffffffffffffffff; 
                        axis_host_send[0].tlast <= 1'b0; 
                        axis_host_send[0].tvalid <= 1'b1;

                        // Save the remainder for the next (and last) chunk
                        stream_remainder_data <= data_stream_data_out[511:480];
                        stream_remainder_keep <= ((1 << (64 - $coutones(data_stream_keep_out)))-1); // Shift the keep bits and add the 4 bits for the meta tag

                        // Release the data chunk and the meta tag from their respective FIFOs
                        data_stream_ready_in <= 1'b1;

                        // Move to the next state to transmit the last chunk 
                        release_state <= TRANSMIT_LAST_CHUNK; 
                    end else begin 
                        // Hooray, the meta tag fits into the first chunk -> Just send it out 
                        axis_host_send[0].tdata [31:0] <= meta_tag_data_out; // First 32 bits are the meta tag
                        axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                        axis_host_send[0].tkeep <= (data_stream_keep_out << 4) | 64'h000000000000000f; // Shift the keep bits and add the 4 bits for the meta tag
                        axis_host_send[0].tlast <= 1;
                        axis_host_send[0].tvalid <= 1'b1;

                        // Release the data chunk and the meta tag from their respective FIFOs 
                        data_stream_ready_in <= 1'b1;

                        // Move to the final state to wait for the finished transmission of the merged packet 
                        release_state <= WAIT_FINAL_TRANSMISSION; 
                    end 
                end else begin  
                    // Normal case: Not yet the last chunk of the data stream to be released -> Merge in and move on
                    axis_host_send[0].tdata [31:0] <= meta_tag_data_out; // First 32 bits are the meta tag
                    axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                    axis_host_send[0].tkeep <= 64'hffffffffffffffff;
                    axis_host_send[0].tlast <= 1'b0;
                    axis_host_send[0].tvalid <= 1'b1;

                    // Save the remainder for the next chunk
                    stream_remainder_data <= data_stream_data_out[511:480];
                    stream_remainder_keep <= 64'h000000000000000f; // Carry on the 4 bits for the meta tag 

                    // Release the data chunk and the meta tag from their respective FIFOs
                    data_stream_ready_in <= 1'b1;

                    // Move to the next state to continue merging the data stream and meta tag
                    release_state <= TRANSMIT_NEXT_CHUNK;
                end
            end 

            // State to transmit the next chunk of the merged data stream and meta tag 
            TRANSMIT_NEXT_CHUNK: begin 

                // Check if the previous chunk has been accepted by the host interface
                if(axis_host_send[0].tready) begin 
                    // Repeat action from above: Check the next fetched data chunk from the FIFO.
                    if(data_stream_last_out) begin 
                        // What if the original data stream only consisted of one chunk?
                        if($countones(data_stream_keep_out) > 60) begin
                            // With the added meta-tag, this would exceed 64 bytes -> Need to split the data stream into two chunks 
                            axis_host_send[0].tdata [31:0] <= stream_remainder_data; // First 32 bits are the meta tag
                            axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                            axis_host_send[0].tkeep <= 64'hffffffffffffffff; 
                            axis_host_send[0].tlast <= 1'b0; 
                            axis_host_send[0].tvalid <= 1'b1;

                            // Save the remainder for the next (and last) chunk
                            stream_remainder_data <= data_stream_data_out[511:480];
                            stream_remainder_keep <= ((1 << (64 - $coutones(data_stream_keep_out)))-1); // Shift the keep bits and add the 4 bits for the meta tag

                            // Release the data chunk and the meta tag from their respective FIFOs
                            data_stream_ready_in <= 1'b1;

                            // Move to the next state to transmit the last chunk 
                            release_state <= TRANSMIT_LAST_CHUNK; 
                        end else begin 
                            // Hooray, the meta tag fits into the first chunk -> Just send it out 
                            axis_host_send[0].tdata [31:0] <= stream_remainder_data; // First 32 bits are the meta tag
                            axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                            axis_host_send[0].tkeep <= (data_stream_keep_out << 4) | 64'h000000000000000f; // Shift the keep bits and add the 4 bits for the meta tag
                            axis_host_send[0].tlast <= 1;
                            axis_host_send[0].tvalid <= 1'b1;

                            // Release the data chunk and the meta tag from their respective FIFOs 
                            data_stream_ready_in <= 1'b1;

                            // Move to the final state to wait for the finished transmission of the merged packet 
                            release_state <= WAIT_FINAL_TRANSMISSION; 
                        end 
                    end else begin  
                        // Normal case: Not yet the last chunk of the data stream to be released -> Merge in and move on
                        axis_host_send[0].tdata [31:0] <= stream_remainder_data; // First 32 bits are the meta tag
                        axis_host_send[0].tdata [511:32] <= data_stream_data_out [479:0]; // Remaining 480 bits are the first 480 bits of the data stream
                        axis_host_send[0].tkeep <= 64'hffffffffffffffff;
                        axis_host_send[0].tlast <= 1'b0;
                        axis_host_send[0].tvalid <= 1'b1;

                        // Save the remainder for the next chunk
                        stream_remainder_data <= data_stream_data_out[511:480];
                        stream_remainder_keep <= 64'h000000000000000f; // Carry on the 4 bits for the meta tag 

                        // Release the data chunk and the meta tag from their respective FIFOs
                        data_stream_ready_in <= 1'b1;

                        // Move to the next state to continue merging the data stream and meta tag
                        release_state <= TRANSMIT_NEXT_CHUNK;
                    end

                end else begin 
                    // Wait, but don't release further chunks from the data stream FIFO 
                    data_stream_ready_in <= 1'b0;

                    // Remain in this state 
                    release_state <= TRANSMIT_NEXT_CHUNK;
                end 
            end 

            // State to transmit the last chunk of the merged data stream
            TRANSMIT_LAST_CHUNK: begin 
                // Stop release from both FIFOs anyways 
                meta_tag_ready_in <= 1'b0;
                data_stream_ready_in <= 1'b0;

                // Check if the previous chunk has been accepted by the host interface
                if(axis_host_send[0].tready) begin
                    axis_host_send[0].tdata [31:0] <= stream_remainder_data; // Remaining bits are the remainder of the data stream
                    axis_host_send[0].tkeep <= stream_remainder_keep;
                    axis_host_send[0].tlast <= 1'b1;
                    axis_host_send[0].tvalid <= 1'b1;

                    // Move to the final state to wait for the finished transmission of the merged packet
                    release_state <= WAIT_FINAL_TRANSMISSION;
                end 
            end 

            // State to wait for the final transmission of the merged data stream 
            WAIT_FINAL_TRANSMISSION: begin 
                // Just wait until the last chunk has been accepted by the host interface
                if(axis_host_send[0].tready) begin
                    // Reset the host interface signals
                    axis_host_send[0].tvalid <= 1'b0;
                    axis_host_send[0].tdata <= 0;
                    axis_host_send[0].tkeep <= 0;
                    axis_host_send[0].tlast <= 0;

                    // Reset the remainder signals 
                    stream_remainder_data <= 0;
                    stream_remainder_keep <= 0;

                    // Move back to the idle state to wait for the next data stream and meta tag
                    release_state <= RELEASE_IDLE;
                end 
            end 

        endcase 
    end 
end


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 5: Combinatorial assignment missing signals  
//
////////////////////////////////////////////////////////////////////////////////

// Assign the data signal of the DMA command 
assign sq_wr.data.last = 1'b1; 
assign sq_wr.data.pid = host_networking_pid;
assign sq_wr.data.vaddr = host_networking_buff_vaddr + (host_networking_ring_tail * host_networking_buff_stride);   // Base address + current ring position 
assign sq_wr.data.len = meta_tag_data_out.packet_len + 4;  // Length of the packet + 4 bytes for the meta tag to be merged into the data stream 
assign sq_wr.data.strm = STRM_HOST;
assign sq_wr.data.opcode = LOCAL_WRITE;
assign sq_wr.data.mode = 0; 
assign sq_wr.data.rdma = 0; 
assign sq_wr.data.vfid = 0; 
assign sq_wr.data.actv = 1; 
assign sq_wr.data.host = 0; 
assign sq_wr.data.offs = 0; 
assign sq_wr.data.rsrvd = 0; 

// Assign the TX-path for outgoing packets 
`AXISR_ASSIGN(axis_host_recv[0], axis_host_networking_tx)


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 7: Tie-off of unused signals 
//  
////////////////////////////////////////////////////////////////////////////////

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


////////////////////////////////////////////////////////////////////////////////
//
// SECTION 8: ILA for debugging purposes
//
////////////////////////////////////////////////////////////////////////////////

ila_host_networking inst_ila_host_networking (
    // Clock signal
    .clk(aclk), 

    // TX-path 
    .probe0(axis_host_networking_tx.tvalid),            // 1
    .probe1(axis_host_networking_tx.tready),            // 1
    .probe2(axis_host_networking_tx.tlast),             // 1
    .probe3(axis_host_networking_tx.tdata),             // 512
    .probe4(axis_host_networking_tx.tkeep),             // 64

    // RX-path 
    .probe5(axis_host_networking_rx.tvalid),            // 1
    .probe6(axis_host_networking_rx.tready),            // 1
    .probe7(axis_host_networking_rx.tlast),             // 1
    .probe8(axis_host_networking_rx.tdata),             // 512       
    .probe9(axis_host_networking_rx.tkeep),             // 64

    // Host Interface RX-path 
    .probe10(axis_host_send[0].tvalid),                 // 1
    .probe11(axis_host_send[0].tready),                 // 1
    .probe12(axis_host_send[0].tlast),                  // 1
    .probe13(axis_host_send[0].tdata),                  // 512
    .probe14(axis_host_send[0].tkeep),                  // 64

    // DMA-command interface 
    .probe15(sq_wr.valid),                              // 1
    .probe16(sq_wr.ready),                              // 1
    .probe17(sq_wr.data),                               // 128

    // AXI-Ctrl interface 
    .probe18(host_networking_buff_vaddr),               // 48
    .probe19(host_networking_buff_stride),              // 48
    .probe20(host_networking_ring_size),                // 48
    .probe21(host_networking_ring_head),                // 48
    .probe22(host_networking_ring_tail),                // 48
    .probe23(host_networking_irq_coalesce),             // 32

    // Reception FSM
    .probe24(reception_state),                          // 4
    .probe25(meta_tag_valid_in),                        // 1
    .probe26(meta_tag_data_in),                         // 32
    .probe27(reception_fsm_ready),                      // 1

    // Release FSM 
    .probe28(release_state),                            // 4
    .probe29(stream_remainder_data),                    // 32
    .probe30(stream_remainder_keep),                    // 64
    .probe31(data_stream_ready_in),                     // 1
    .probe32(meta_tag_ready_in),                        // 1

    // Data Stream FIFO
    .probe33(data_stream_valid_out),                    // 1
    .probe34(data_stream_data_out),                     // 512
    .probe35(data_stream_keep_out),                     // 64
    .probe36(data_stream_last_out)                      // 1    
); 