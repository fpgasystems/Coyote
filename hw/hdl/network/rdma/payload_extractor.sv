///////////////////////////////////////////////////////////////////////////////
//
// Payload extractor - looks at incoming network traffic and extracts payload 
// (on 512 Bit AXI-Stream) and Meta-Information (Opcode, QPN) on dedicated interfaces
//
///////////////////////////////////////////////////////////////////////////////

module payload_extractor(
    // Incoming clock and reset 
    input logic nclk, 
    input logic nresetn, 

    // Incoming stream of network traffic - split up AXI4-Stream fields (no ready required)
    input logic[511:0] m_axis_rx_data_i, 
    input logic [63:0] m_axis_rx_keep_i, 
    input logic m_axis_rx_valid_i, 
    input logic m_axis_rx_last_i, 

    // Outgoing stream of extracted payload 
    AXI4S.m m_axis_payload_tx, 

    // Outgoing Meta-Information consisting of QPN and opcode 
    output logic [31:0] meta_tx_o
); 

    ////////////////////////////////////////////////////////////////////////
    //
    // Definition of localparams as required for the calculation 
    //
    ////////////////////////////////////////////////////////////////////////

    localparam lp_opcode_write_first = 8'h06; 
    localparam lp_opcode_write_middle = 8'h07; 
    localparam lp_opcode_write_last = 8'h08; 
    localparam lp_opcode_write_only = 8'h0a; 

    ////////////////////////////////////////////////////////////////////////
    //
    // Definition of data types
    //
    ///////////////////////////////////////////////////////////////////////

    // 512 Bit Data Type to hold the incoming words 
    typedef logic [511:0] DataWord; 

    // Pointer to indicate fill-level of the DataWord 
    typedef logic [9:0] DataFillIndicator; 

    // 64 Bit Data Type to hold the keep signal 
    typedef logic [63:0] DataKeep; 

    // 24 Bit Signal to hold the QPN for meta-information 
    typedef logic [23:0] MetaQPN; 

    // 8 Bit Signal to hold the RDMA-Opcode 
    typedef logic [7:0] MetaOpcode; 

    // Combine QPN and Opcode to a single Meta-Datatype 
    typedef struct packed{
        MetaQPN QPN;
        MetaOpcode Opcode;
    } MetaInformation; 

    // Definition of FSM-states 
    typedef enum logic[2:0] {
        IDLE = 0, 
        SUBSEQUENT = 1, 
        FINAL = 2, 
        WAIT_SEND_LAST = 3
    } FSMState; 


    /////////////////////////////////////////////////////////////////////////////////
    //
    // Definition of all required registers 
    //
    /////////////////////////////////////////////////////////////////////////////////

    // Register to hold extracted payload
    DataWord payload_word[2]; 

    // Register to hold upcounted keep-value
    DataKeep payload_keep[2]; 

    // Register to hold last-value
    logic payload_last[2]; 
    
    // Register to hold valid-value 
    logic payload_valid[2]; 

    // Pointers to indicate fill-level of payload-words
    DataFillIndicator payload_fill_indicator[2]; 

    // Selector for the payload_word 
    logic payload_word_selector; 
    logic payload_next_word_selector; 

    // Register with Meta-Information for an ongoing flow of communication 
    MetaInformation current_transmission_meta; 

    // FSM state-variable 
    FSMState fsm_state; 

    // Wires for extraction of QPN and RDMA-opcode 
    MetaQPN qpn_extractor; 
    MetaOpcode opcode_extractor; 

    // Logic signal to show whether the incoming operation is of WRITE-type and thus carries payload
    logic is_of_write_type; 
    logic without_exh; 

    // Logic signals to determine whether incoming packets are actually RDMA-traffic 
    logic RDMA_marker_present; 
    logic marker_1; 
    logic marker_2; 
    logic marker_3; 

    // Reversed reset for sanity 
    logic rst_inverted;  

    // Signal to calculate the amount of usable payload bits in the last Stream-burst 
    DataFillIndicator usable_bits_last_chunk; 


    //////////////////////////////////////////////////////////////////////
    // 
    // Combinatorial Logic for extraction of meta-information 
    //
    //////////////////////////////////////////////////////////////////////

    // Invert the reset
    assign rst_inverted = ~nresetn; 

    // Extract opcode and qpn 
    assign opcode_extractor = m_axis_rx_data_i[231:224]; 
    assign qpn_extractor = m_axis_rx_data_i[287:264]; 

    // Determine if the incoming packet is of WRITE-type and carries extractable payload
    assign is_of_write_type = (opcode_extractor == lp_opcode_write_first) || (opcode_extractor == lp_opcode_write_last) || (opcode_extractor == lp_opcode_write_middle) || (opcode_extractor == lp_opcode_write_only); 

    // Assure that the packet is actually RDMA
    assign marker_1 = (m_axis_rx_data_i[15:0] == 16'h0245); 
    assign marker_2 = (m_axis_rx_data_i[79:72] == 8'h11); 
    assign marker_3 = (m_axis_rx_data_i[291:288] == 4'h0); 
    assign RDMA_marker_present = marker_1 && marker_2 && marker_3; 

    // Assign the meta-output to the current meta-register 
    assign meta_tx_o = current_transmission_meta; 

    // AXI-Output can be taken from the two buffering-registers in the module 
    assign m_axis_payload_tx.tkeep = payload_valid[0] ? payload_keep[0] : payload_keep[1]; 
    assign m_axis_payload_tx.tvalid = payload_valid[0] || payload_valid[1]; 
    assign m_axis_payload_tx.tlast = payload_valid[0] ? payload_last[0] : payload_last[1]; 

    // Assign the selector for the next word 
    assign payload_next_word_selector = payload_word_selector ? 0 : 1; 

    // Combinatorial logic for the AXI-data output to re-order the bytes as required for the ML-model 
    always_comb begin 
        if(payload_valid[0]) begin 
            m_axis_payload_tx.tdata[7:0] = payload_word[0][511:504];
            m_axis_payload_tx.tdata[15:8] = payload_word[0][503:496];
            m_axis_payload_tx.tdata[23:16] = payload_word[0][495:488];
            m_axis_payload_tx.tdata[31:24] = payload_word[0][487:480];
            m_axis_payload_tx.tdata[39:32] = payload_word[0][479:472];
            m_axis_payload_tx.tdata[47:40] = payload_word[0][471:464];
            m_axis_payload_tx.tdata[55:48] = payload_word[0][463:456];
            m_axis_payload_tx.tdata[63:56] = payload_word[0][455:448];
            m_axis_payload_tx.tdata[71:64] = payload_word[0][447:440];
            m_axis_payload_tx.tdata[79:72] = payload_word[0][439:432];
            m_axis_payload_tx.tdata[87:80] = payload_word[0][431:424];
            m_axis_payload_tx.tdata[95:88] = payload_word[0][423:416];
            m_axis_payload_tx.tdata[103:96] = payload_word[0][415:408];
            m_axis_payload_tx.tdata[111:104] = payload_word[0][407:400];
            m_axis_payload_tx.tdata[119:112] = payload_word[0][399:392];
            m_axis_payload_tx.tdata[127:120] = payload_word[0][391:384];
            m_axis_payload_tx.tdata[135:128] = payload_word[0][383:376];
            m_axis_payload_tx.tdata[143:136] = payload_word[0][375:368];
            m_axis_payload_tx.tdata[151:144] = payload_word[0][367:360];
            m_axis_payload_tx.tdata[159:152] = payload_word[0][359:352];
            m_axis_payload_tx.tdata[167:160] = payload_word[0][351:344];
            m_axis_payload_tx.tdata[175:168] = payload_word[0][343:336];
            m_axis_payload_tx.tdata[183:176] = payload_word[0][335:328];
            m_axis_payload_tx.tdata[191:184] = payload_word[0][327:320];
            m_axis_payload_tx.tdata[199:192] = payload_word[0][319:312];
            m_axis_payload_tx.tdata[207:200] = payload_word[0][311:304];
            m_axis_payload_tx.tdata[215:208] = payload_word[0][303:296];
            m_axis_payload_tx.tdata[223:216] = payload_word[0][295:288];
            m_axis_payload_tx.tdata[231:224] = payload_word[0][287:280];
            m_axis_payload_tx.tdata[239:232] = payload_word[0][279:272];
            m_axis_payload_tx.tdata[247:240] = payload_word[0][271:264];
            m_axis_payload_tx.tdata[255:248] = payload_word[0][263:256];
            m_axis_payload_tx.tdata[263:256] = payload_word[0][255:248];
            m_axis_payload_tx.tdata[271:264] = payload_word[0][247:240];
            m_axis_payload_tx.tdata[279:272] = payload_word[0][239:232];
            m_axis_payload_tx.tdata[287:280] = payload_word[0][231:224];
            m_axis_payload_tx.tdata[295:288] = payload_word[0][223:216];
            m_axis_payload_tx.tdata[303:296] = payload_word[0][215:208];
            m_axis_payload_tx.tdata[311:304] = payload_word[0][207:200];
            m_axis_payload_tx.tdata[319:312] = payload_word[0][199:192];
            m_axis_payload_tx.tdata[327:320] = payload_word[0][191:184];
            m_axis_payload_tx.tdata[335:328] = payload_word[0][183:176];
            m_axis_payload_tx.tdata[343:336] = payload_word[0][175:168];
            m_axis_payload_tx.tdata[351:344] = payload_word[0][167:160];
            m_axis_payload_tx.tdata[359:352] = payload_word[0][159:152];
            m_axis_payload_tx.tdata[367:360] = payload_word[0][151:144];
            m_axis_payload_tx.tdata[375:368] = payload_word[0][143:136];
            m_axis_payload_tx.tdata[383:376] = payload_word[0][135:128];
            m_axis_payload_tx.tdata[391:384] = payload_word[0][127:120];
            m_axis_payload_tx.tdata[399:392] = payload_word[0][119:112];
            m_axis_payload_tx.tdata[407:400] = payload_word[0][111:104];
            m_axis_payload_tx.tdata[415:408] = payload_word[0][103:96];
            m_axis_payload_tx.tdata[423:416] = payload_word[0][95:88];
            m_axis_payload_tx.tdata[431:424] = payload_word[0][87:80];
            m_axis_payload_tx.tdata[439:432] = payload_word[0][79:72];
            m_axis_payload_tx.tdata[447:440] = payload_word[0][71:64];
            m_axis_payload_tx.tdata[455:448] = payload_word[0][63:56];
            m_axis_payload_tx.tdata[463:456] = payload_word[0][55:48];
            m_axis_payload_tx.tdata[471:464] = payload_word[0][47:40];
            m_axis_payload_tx.tdata[479:472] = payload_word[0][39:32];
            m_axis_payload_tx.tdata[487:480] = payload_word[0][31:24];
            m_axis_payload_tx.tdata[495:488] = payload_word[0][23:16];
            m_axis_payload_tx.tdata[503:496] = payload_word[0][15:8];
            m_axis_payload_tx.tdata[511:504] = payload_word[0][7:0]; 
        end else begin 
            m_axis_payload_tx.tdata[7:0] = payload_word[1][511:504];
            m_axis_payload_tx.tdata[15:8] = payload_word[1][503:496];
            m_axis_payload_tx.tdata[23:16] = payload_word[1][495:488];
            m_axis_payload_tx.tdata[31:24] = payload_word[1][487:480];
            m_axis_payload_tx.tdata[39:32] = payload_word[1][479:472];
            m_axis_payload_tx.tdata[47:40] = payload_word[1][471:464];
            m_axis_payload_tx.tdata[55:48] = payload_word[1][463:456];
            m_axis_payload_tx.tdata[63:56] = payload_word[1][455:448];
            m_axis_payload_tx.tdata[71:64] = payload_word[1][447:440];
            m_axis_payload_tx.tdata[79:72] = payload_word[1][439:432];
            m_axis_payload_tx.tdata[87:80] = payload_word[1][431:424];
            m_axis_payload_tx.tdata[95:88] = payload_word[1][423:416];
            m_axis_payload_tx.tdata[103:96] = payload_word[1][415:408];
            m_axis_payload_tx.tdata[111:104] = payload_word[1][407:400];
            m_axis_payload_tx.tdata[119:112] = payload_word[1][399:392];
            m_axis_payload_tx.tdata[127:120] = payload_word[1][391:384];
            m_axis_payload_tx.tdata[135:128] = payload_word[1][383:376];
            m_axis_payload_tx.tdata[143:136] = payload_word[1][375:368];
            m_axis_payload_tx.tdata[151:144] = payload_word[1][367:360];
            m_axis_payload_tx.tdata[159:152] = payload_word[1][359:352];
            m_axis_payload_tx.tdata[167:160] = payload_word[1][351:344];
            m_axis_payload_tx.tdata[175:168] = payload_word[1][343:336];
            m_axis_payload_tx.tdata[183:176] = payload_word[1][335:328];
            m_axis_payload_tx.tdata[191:184] = payload_word[1][327:320];
            m_axis_payload_tx.tdata[199:192] = payload_word[1][319:312];
            m_axis_payload_tx.tdata[207:200] = payload_word[1][311:304];
            m_axis_payload_tx.tdata[215:208] = payload_word[1][303:296];
            m_axis_payload_tx.tdata[223:216] = payload_word[1][295:288];
            m_axis_payload_tx.tdata[231:224] = payload_word[1][287:280];
            m_axis_payload_tx.tdata[239:232] = payload_word[1][279:272];
            m_axis_payload_tx.tdata[247:240] = payload_word[1][271:264];
            m_axis_payload_tx.tdata[255:248] = payload_word[1][263:256];
            m_axis_payload_tx.tdata[263:256] = payload_word[1][255:248];
            m_axis_payload_tx.tdata[271:264] = payload_word[1][247:240];
            m_axis_payload_tx.tdata[279:272] = payload_word[1][239:232];
            m_axis_payload_tx.tdata[287:280] = payload_word[1][231:224];
            m_axis_payload_tx.tdata[295:288] = payload_word[1][223:216];
            m_axis_payload_tx.tdata[303:296] = payload_word[1][215:208];
            m_axis_payload_tx.tdata[311:304] = payload_word[1][207:200];
            m_axis_payload_tx.tdata[319:312] = payload_word[1][199:192];
            m_axis_payload_tx.tdata[327:320] = payload_word[1][191:184];
            m_axis_payload_tx.tdata[335:328] = payload_word[1][183:176];
            m_axis_payload_tx.tdata[343:336] = payload_word[1][175:168];
            m_axis_payload_tx.tdata[351:344] = payload_word[1][167:160];
            m_axis_payload_tx.tdata[359:352] = payload_word[1][159:152];
            m_axis_payload_tx.tdata[367:360] = payload_word[1][151:144];
            m_axis_payload_tx.tdata[375:368] = payload_word[1][143:136];
            m_axis_payload_tx.tdata[383:376] = payload_word[1][135:128];
            m_axis_payload_tx.tdata[391:384] = payload_word[1][127:120];
            m_axis_payload_tx.tdata[399:392] = payload_word[1][119:112];
            m_axis_payload_tx.tdata[407:400] = payload_word[1][111:104];
            m_axis_payload_tx.tdata[415:408] = payload_word[1][103:96];
            m_axis_payload_tx.tdata[423:416] = payload_word[1][95:88];
            m_axis_payload_tx.tdata[431:424] = payload_word[1][87:80];
            m_axis_payload_tx.tdata[439:432] = payload_word[1][79:72];
            m_axis_payload_tx.tdata[447:440] = payload_word[1][71:64];
            m_axis_payload_tx.tdata[455:448] = payload_word[1][63:56];
            m_axis_payload_tx.tdata[463:456] = payload_word[1][55:48];
            m_axis_payload_tx.tdata[471:464] = payload_word[1][47:40];
            m_axis_payload_tx.tdata[479:472] = payload_word[1][39:32];
            m_axis_payload_tx.tdata[487:480] = payload_word[1][31:24];
            m_axis_payload_tx.tdata[495:488] = payload_word[1][23:16];
            m_axis_payload_tx.tdata[503:496] = payload_word[1][15:8];
            m_axis_payload_tx.tdata[511:504] = payload_word[1][7:0];
        end 
    end 


    //////////////////////////////////////////////////////////////////////
    //
    // Sequential Logic: FSM to deal with incoming traffic 
    //
    //////////////////////////////////////////////////////////////////////

    always_ff @(posedge nclk) begin 
        if(rst_inverted) begin 
            // Reset the required registers 
            for(integer output_counter = 0; output_counter < 2; output_counter++) begin 
                payload_word[output_counter] <= 512'b0; 
                payload_keep[output_counter] <= 64'b0; 
                payload_valid[output_counter] <= 1'b0; 
                payload_last[output_counter] <= 1'b0; 
                payload_fill_indicator[output_counter] <= 9'b0; 
            end 
            
            // Reset the word selector 
            payload_word_selector <= 1'b0; 

            // Reset the meta regs for the ongoing communication 
            current_transmission_meta.QPN <= 24'b0; 
            current_transmission_meta.Opcode <= 8'b0; 

            // Reset the FSM to its starting state 
            fsm_state <= IDLE; 

            without_exh <= 0; 

            // Reset the output interfaces 
            /*m_axis_payload_tx.tvalid <= 1'b0;
            m_axis_payload_tx.tdata <= 512'b0;
            m_axis_payload_tx.tkeep <= 64'b0;
            m_axis_payload_tx.tlast <= 1'b0;
            meta_tx_o <= 32'b0;*/

        end else begin 
            // FSM to deal with the incoming data 
            case(fsm_state) 
                IDLE: begin 
                    // Only begin to process if there's a new transmission coming in & it's of type WRITE (carries payload that can be taken out)
                    if(m_axis_rx_valid_i && is_of_write_type && RDMA_marker_present) begin 
                        // Store current meta-information as dependent on the just started transmission 
                        current_transmission_meta.QPN <= qpn_extractor; 
                        current_transmission_meta.Opcode <= opcode_extractor; 

                        // Store first part of the payload in the current payload register
                        if((opcode_extractor == lp_opcode_write_middle) || (opcode_extractor == lp_opcode_write_last)) begin 
                            payload_word[payload_word_selector][191:0] <= m_axis_rx_data_i[511:320]; 
                            payload_keep[payload_word_selector][23:0] <= 24'hffffff; 
                            payload_keep[payload_word_selector][63:24] <= 40'b0; 
                            without_exh <= 1'b1;
                        end else begin 
                            payload_word[payload_word_selector][63:0] <= m_axis_rx_data_i[511:448]; 
                            payload_keep[payload_word_selector][7:0] <= 8'hff; 
                            payload_keep[payload_word_selector][63:8] <= 56'b0; 
                            without_exh <= 1'b0;
                        end  
                        
                        // Check whether this first message is also the last - interesting, but ok
                        if(m_axis_rx_last_i) begin 
                            payload_valid[payload_word_selector] <= 1'b1; 
                            payload_last[payload_word_selector] <= 1'b1; 
                            fsm_state <= WAIT_SEND_LAST; 
                        end else begin    
                            payload_valid[payload_word_selector] <= 1'b0; 
                            payload_last[payload_word_selector] <= 1'b0; 
                            fsm_state <= SUBSEQUENT; 

                            // Set fill-counter 
                            payload_fill_indicator[payload_word_selector] <= 10'd64; 
                        end
                    end 
                end 

                SUBSEQUENT: begin 
                    // Anyways: Reset the valid-signal of the currently inactive output register 
                    payload_valid[payload_next_word_selector] <= 1'b0; 
                    payload_last[payload_next_word_selector] <= 1'b0; 
                    payload_keep[payload_next_word_selector] <= 64'b0; 
                    payload_word[payload_next_word_selector] <= 512'b0;  

                    // Check if there's new input available
                    if(m_axis_rx_valid_i) begin 
                        // Check if this input has last-flag set 
                        if(m_axis_rx_last_i) begin 
                            // If that's the last chunk, we need to consult the keep-signal and take the ICRC-offset into account to get the remaining payload-bits 
                            case(m_axis_rx_keep_i)
                                64'h000000000000000f: begin 
                                    // It's just the CRC, so no data for us! 
                                    payload_valid[payload_word_selector] <= 1'b1; 
                                    payload_last[payload_word_selector] <= 1'b1; 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h00000000000000ff: begin 
                                    // 32 Bit of Payload for us, fits in the open register
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1;
                                        payload_word[payload_word_selector][223:192] <= m_axis_rx_data_i[31:0];  
                                        payload_keep[payload_word_selector][27:0] <= 28'hfffffff; 
                                        payload_keep[payload_word_selector][63:28] <= 36'b0; 
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1;
                                        payload_word[payload_word_selector][95:64] <= m_axis_rx_data_i[31:0];  
                                        payload_keep[payload_word_selector][11:0] <= 12'hfff; 
                                        payload_keep[payload_word_selector][63:12] <= 52'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h0000000000000fff: begin 
                                    // 64 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][255:192] <= m_axis_rx_data_i[63:0]; 
                                        payload_keep[payload_word_selector][31:0] <= 32'hffffffff; 
                                        payload_keep[payload_word_selector][63:24] <= 32'b0; 
                                    end else begin
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][127:64] <= m_axis_rx_data_i[63:0]; 
                                        payload_keep[payload_word_selector][15:0] <= 16'hffff; 
                                        payload_keep[payload_word_selector][63:16] <= 48'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h000000000000ffff: begin 
                                    // 96 Bit of Payload for us, fits in the open register
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][287:192] <= m_axis_rx_data_i[95:0]; 
                                        payload_keep[payload_word_selector][35:0] <= 36'hfffffff; 
                                        payload_keep[payload_word_selector][63:36] <= 28'b0; 
                                    end else begin
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][159:64] <= m_axis_rx_data_i[95:0]; 
                                        payload_keep[payload_word_selector][19:0] <= 20'hfffff; 
                                        payload_keep[payload_word_selector][63:20] <= 44'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h00000000000fffff: begin 
                                    // 128 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][319:192] <= m_axis_rx_data_i[127:0]; 
                                        payload_keep[payload_word_selector][39:0] <= 40'hffffffffff; 
                                        payload_keep[payload_word_selector][63:40] <= 24'b0; 
                                    end else begin
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][191:64] <= m_axis_rx_data_i[127:0]; 
                                        payload_keep[payload_word_selector][23:0] <= 24'hffffff; 
                                        payload_keep[payload_word_selector][63:24] <= 40'b0; 
                                    end

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h0000000000ffffff: begin 
                                    // 160 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][351:192] <= m_axis_rx_data_i[159:0]; 
                                        payload_keep[payload_word_selector][43:0] <= 44'hfffffffffff; 
                                        payload_keep[payload_word_selector][63:44] <= 20'b0; 
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][223:64] <= m_axis_rx_data_i[159:0];
                                        payload_keep[payload_word_selector][27:0] <= 28'hfffffff; 
                                        payload_keep[payload_word_selector][63:28] <= 36'b0;  
                                    end

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h000000000fffffff: begin 
                                    // 192 Bit of Payload for us, fits in the open register
                                    if(without_exh) begin
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][383:192] <= m_axis_rx_data_i[191:0]; 
                                        payload_keep[payload_word_selector][47:0] <= 48'hffffffffffff; 
                                        payload_keep[payload_word_selector][63:48] <= 16'b0; 
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][255:64] <= m_axis_rx_data_i[191:0]; 
                                        payload_keep[payload_word_selector][31:0] <= 32'hffffffff; 
                                        payload_keep[payload_word_selector][63:32] <= 32'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h00000000ffffffff: begin 
                                    // 224 Bit of Payload for us, fits in the open register
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][415:192] <= m_axis_rx_data_i[223:0]; 
                                        payload_keep[payload_word_selector][51:0] <= 52'hfffffffffffff; 
                                        payload_keep[payload_word_selector][63:52] <= 12'b0;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][287:64] <= m_axis_rx_data_i[223:0]; 
                                        payload_keep[payload_word_selector][35:0] <= 36'hfffffffff; 
                                        payload_keep[payload_word_selector][63:36] <= 28'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h0000000fffffffff: begin 
                                    // 256 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][447:192] <= m_axis_rx_data_i[255:0]; 
                                        payload_keep[payload_word_selector][55:0] <= 56'hffffffffffffff; 
                                        payload_keep[payload_word_selector][63:56] <= 8'b0;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][319:64] <= m_axis_rx_data_i[255:0];
                                        payload_keep[payload_word_selector][39:0] <= 40'hffffffffff; 
                                        payload_keep[payload_word_selector][63:40] <= 24'b0;
                                    end   

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h000000ffffffffff: begin 
                                    // 288 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][479:192] <= m_axis_rx_data_i[287:0]; 
                                        payload_keep[payload_word_selector][59:0] <= 60'hfffffffffffffff; 
                                        payload_keep[payload_word_selector][63:60] <= 4'b0;
                                    end else begin
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][351:64] <= m_axis_rx_data_i[287:0]; 
                                        payload_keep[payload_word_selector][43:0] <= 44'hfffffffffff; 
                                        payload_keep[payload_word_selector][63:44] <= 20'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h00000fffffffffff: begin 
                                    // 320 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 
                                        // payload_keep[payload_word_selector][63:56] <= 8'b0; 
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][383:64] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][47:0] <= 48'hffffffffffff; 
                                        payload_keep[payload_word_selector][63:48] <= 16'b0; 
                                    end 

                                    // Go to last state 
                                    fsm_state <= WAIT_SEND_LAST; 
                                end 

                                64'h0000ffffffffffff: begin 
                                    // 352 Bit of Payload for us, fits in the open register
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][31:0] <= m_axis_rx_data_i[351:320];
                                        payload_last[payload_next_word_selector] <= 1'b1;
                                        payload_keep[payload_next_word_selector][3:0] <= 4'hf;
                                        payload_keep[payload_next_word_selector][63:4] <= 60'h0;

                                        fsm_state <= FINAL;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][415:64] <= m_axis_rx_data_i[351:0]; 
                                        payload_keep[payload_word_selector][51:0] <= 52'hfffffffffffff; 
                                        payload_keep[payload_word_selector][63:52] <= 12'b0;

                                        // Go to last state 
                                        fsm_state <= WAIT_SEND_LAST; 
                                    end  
                                end 

                                64'h000fffffffffffff: begin 
                                    // 384 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][63:0] <= m_axis_rx_data_i[383:320];
                                        payload_last[payload_next_word_selector] <= 1'b1;
                                        payload_keep[payload_next_word_selector][7:0] <= 8'hff;
                                        payload_keep[payload_next_word_selector][63:8] <= 56'h0;

                                        fsm_state <= FINAL;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][447:64] <= m_axis_rx_data_i[383:0]; 
                                        payload_keep[payload_word_selector][55:0] <= 56'hffffffffffffff; 
                                        payload_keep[payload_word_selector][63:56] <= 8'b0; 

                                        // Go to last state 
                                        fsm_state <= WAIT_SEND_LAST; 
                                    end 
                                end 

                                64'h00ffffffffffffff: begin 
                                    // 416 Bit of Payload for us, fits in the open register 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][95:0] <= m_axis_rx_data_i[415:320];
                                        payload_last[payload_next_word_selector] <= 1'b1;
                                        payload_keep[payload_next_word_selector][11:0] <= 12'hfff;
                                        payload_keep[payload_next_word_selector][63:12] <= 52'h0;

                                        fsm_state <= FINAL;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][479:64] <= m_axis_rx_data_i[415:0]; 
                                        payload_keep[payload_word_selector][59:0] <= 60'hfffffffffffffff; 
                                        payload_keep[payload_word_selector][63:60] <= 4'b0; 

                                        // Go to last state 
                                        fsm_state <= WAIT_SEND_LAST;
                                    end  
                                end 

                                64'h0fffffffffffffff: begin 
                                    // 448 Bit of Payload for us, fits in the open register (for the last time) 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][127:0] <= m_axis_rx_data_i[447:320];
                                        payload_last[payload_next_word_selector] <= 1'b1;
                                        payload_keep[payload_next_word_selector][15:0] <= 16'hffff;
                                        payload_keep[payload_next_word_selector][63:16] <= 48'h0;

                                        fsm_state <= FINAL;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b1; 
                                        payload_word[payload_word_selector][511:64] <= m_axis_rx_data_i[447:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 
                                        // Go to last state 
                                        fsm_state <= WAIT_SEND_LAST; 
                                    end 
                                end 

                                64'hffffffffffffffff: begin 
                                    // 480 Bit of Payload for us, has to be split up into both registers 
                                    if(without_exh) begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][159:0] <= m_axis_rx_data_i[479:320];
                                        payload_last[payload_next_word_selector] <= 1'b1;
                                        payload_keep[payload_next_word_selector][19:0] <= 20'hfffff;
                                        payload_keep[payload_next_word_selector][63:20] <= 44'h0;
                                    end else begin 
                                        payload_valid[payload_word_selector] <= 1'b1; 
                                        payload_last[payload_word_selector] <= 1'b0; 
                                        payload_word[payload_word_selector][511:64] <= m_axis_rx_data_i[447:0]; 
                                        payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                        payload_word[payload_next_word_selector][31:0] <= m_axis_rx_data_i[511:448]; 
                                        payload_last[payload_next_word_selector] <= 1'b1; 
                                        payload_keep[payload_next_word_selector][3:0] <= 4'hf; 
                                        payload_keep[payload_next_word_selector][63:4] <= 60'b0; 
                                    end 

                                    // Go to second to last state 
                                    fsm_state <= FINAL; 
                                end 
                            endcase
                            
                        end else begin 
                            // If not, we can assume full 512 bits of data that has to be distributed among the two registers 
                            if(without_exh) begin 
                                payload_valid[payload_word_selector] <= 1'b1; 
                                payload_last[payload_word_selector] <= 1'b0; 
                                payload_word[payload_word_selector][511:192] <= m_axis_rx_data_i[319:0]; 
                                payload_keep[payload_word_selector][63:0] <= 64'hffffffffffffffff; 

                                payload_word[payload_next_word_selector][191:0] <= m_axis_rx_data_i[511:320];
                                payload_last[payload_next_word_selector] <= 1'b0;
                                payload_valid[payload_next_word_selector] <= 1'b0;
                                payload_keep[payload_next_word_selector][23:0] <= 24'hffffff;
                                payload_keep[payload_next_word_selector][63:24] <= 40'h0;
                            end else begin
                                // Fill up the first register 
                                payload_word[payload_word_selector][511:64] <= m_axis_rx_data_i[447:0]; 
                                payload_keep[payload_word_selector][63:8] <= 56'hffffffffffffff; 
                                payload_valid[payload_word_selector] <= 1'b1; 
                                payload_last[payload_word_selector] <= 1'b0; 
                                //payload_fill_indicator <= 10'd512; 
                                
                                // Fill the rest in the second register 
                                payload_word[payload_next_word_selector][447:0] <= m_axis_rx_data_i[511:448]; 
                                payload_keep[payload_next_word_selector][7:0] <= 8'hff; 
                                payload_valid[payload_next_word_selector] <= 1'b0; 
                                payload_last[payload_next_word_selector] <= 1'b0; 
                            end

                            // Increment the payload_word_selector to point to the other register 
                            payload_word_selector <= payload_word_selector + 1; 

                            // Return to this state to wait for the next incoming message-chunk 
                            fsm_state <= SUBSEQUENT; 
                        end 
                    end 
                end 

                FINAL: begin 
                    // Reset the currently active register and activate the other register to transmit the payload 
                    payload_word[payload_word_selector][511:0] <= 512'b0; 
                    payload_keep[payload_word_selector][63:0] <= 64'b0; 
                    payload_valid[payload_word_selector] <= 1'b0; 
                    payload_last[payload_word_selector] <= 1'b0; 

                    // Activate the other register
                    payload_valid[payload_next_word_selector] <= 1'b1;  

                    fsm_state <= WAIT_SEND_LAST; 
                end 

                WAIT_SEND_LAST: begin 
                    // Reset both registers just to make sure 
                    for(integer output_counter = 0; output_counter < 2; output_counter++) begin 
                        payload_word[output_counter] <= 512'b0; 
                        payload_keep[output_counter] <= 64'b0; 
                        payload_valid[output_counter] <= 1'b0; 
                        payload_last[output_counter] <= 1'b0; 
                        payload_fill_indicator[output_counter] <= 9'b0; 
                    end 

                    // Reset the payload_word_selector to start at register 0 with a clean cut 
                    payload_word_selector <= 1'b0; 

                    // Return to initial IDLE-state to wait for new incoming traffic 
                    fsm_state <= IDLE; 
                end 
            endcase
        end 
    end 

endmodule