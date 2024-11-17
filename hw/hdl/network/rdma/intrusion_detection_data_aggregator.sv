/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Data aggregator in front of the RDMA packet processing pipeline - combines payloads of belonging streams to chunks of 512 bits each
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module intrusion_detection_data_aggregator(
    // Incoming clock and reset 
    input logic nclk, 
    input logic nresetn, 

    // Incoming Data Stream from the networking stack 
    AXI4S.s m_axis_rx, 

    // Outgoing decision signal for the QPN under supervision at the moment 
    output logic acceptable_traffic_o, 

    // Outgoing marker signal for the QPN under supervision at the moment
    output logic[23:0] qpn_traffic_o
); 

    ////////////////////////////////////////////////////////////////////////////////////////
    //
    // Definition of localparams as required for the calculations 
    //
    ///////////////////////////////////////////////////////////////////////////////////////
    
    // Definition of the localparams for the decoded opcodes in the headers 
    localparam lp_opcode_write_first = 8'h06; 
    localparam lp_opcode_write_middle = 8'h07; 
    localparam lp_opcode_write_last = 8'h08; 
    localparam lp_opcode_write_only = 8'h0a; 


    ///////////////////////////////////////////////////////////////////////////////////////
    //
    // Definition of data types 
    //
    //////////////////////////////////////////////////////////////////////////////////////

    // 512 Bit Data Type to hold the incoming words 
    typedef logic [511:0] DataWord; 

    // 24 Bit Data Type for QPNs 
    typedef logic [23:0] QPN; 

    // Combined Data Type for a QPN and its acceptance bit 
    typedef struct packed{
        QPN chunk_qpn; 
        logic chunk_valid; 
        logic chunk_decision; 
    } DecisionCombinator; 

    // Combined Data Type for a QPN and its Last-Bit 
    typedef struct packed{
        QPN chunk_qpn; 
        logic chunk_valid; 
        logic chunk_last;
    } PipelineChunk; 

    // 32 Bit Data Type for the DMA length counter 
    typedef logic [31:0] DMALength; 

    


    /////////////////////////////////////////////////////////////////////////////////////////
    //
    // Definition of required registers and registerfiles 
    //
    /////////////////////////////////////////////////////////////////////////////////////////

    // Wires to extract opcode and QPN from the headers of incoming packets 
    logic [7:0] opcode_extractor; 
    QPN qpn_extractor;  

    // Regs for sidechannelling the ML-pipeline with QPN and last-flag over 16 pipeline stages for ML-core #1 and #2
    PipelineChunk qpn_sidechannel_ml_1 [16]; 
    PipelineChunk qpn_sidechannel_ml_2 [16]; 

    // Final registerfile to keep track of all QPNs under supervision at the moment 
    DecisionCombinator decision_combinator[16]; 

    // Reg to store the current QPN if multiple 512-bit lines for a single message are received in the beginning 
    QPN current_qpn; 

    // Reg to store if there's an ongoing transmission at the moment 
    logic current_transmission; 


    ///////////////////////////////////////////////////////////////////////////////////////////
    //
    // Combinatorial logic 
    // 
    //////////////////////////////////////////////////////////////////////////////////////////

    // ML-model is always ready to receive new input, no backpressure provided  
    assign m_axis_rx.tready = 1; 

    // Extract opcode and QPN from the headers of incoming packets for easier comparisons 
    assign opcode_extractor = m_axis_rx.tdata[231:224]; 
    assign qpn_extractor = m_axis_rx.tdata[287:264]; 


    //////////////////////////////////////////////////////////////////////////////////////////
    //
    // Sequential logic 
    //
    //////////////////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge nclk) begin 
        if(!nresetn) begin
            
            // Reset the registerfile for output combination at the end of the pipeline 
            for(integer reg_file_cnt = 0; reg_file_cnt < 16; reg_file_cnt++) begin 
                decision_combinator[reg_file_cnt].chunk_qpn <= 24'b0; 
                decision_combinator[reg_file_cnt].chunk_valid <= 1'b0;
                decision_combinator[reg_file_cnt].chunk_decision <= 1'b0; 
            end 

            // Reset of the sidechannel pipelines 
            for(integer pipeline_cnt = 0; pipeline_cnt < 16; pipeline_cnt++) begin 
                qpn_sidechannel_ml_1[pipeline_cnt].chunk_qpn <= 24'b0; 
                qpn_sidechannel_ml_1[pipeline_cnt].chunk_valid <= 1'b0; 
                qpn_sidechannel_ml_1[pipeline_cnt].chunk_last <= 1'b0; 
                qpn_sidechannel_ml_2[pipeline_cnt].chunk_qpn <= 24'b0; 
                qpn_sidechannel_ml_2[pipeline_cnt].chunk_valid <= 1'b0; 
                qpn_sidechannel_ml_2[pipeline_cnt].chunk_last <= 1'b0; 
            end 

            // Reset of the current QPN
            current_qpn <= 24'b0; 

            // Reset of the current transmission 
            current_transmission <= 1'b0; 

        end else begin 
            // Check for incoming traffic 
            if(m_axis_rx.tvalid) begin 
                // Check if there is already an ongoing / registered transmission to which this chunk of data belongs to 
                if(!ongoing_transmission) begin 
                    // Step 1: Check if the incoming burst is a WRITE - only such are treated
                    if(opcode_extractor == lp_opcode_write_first || opcode_extractor == lp_opcode_write_last || opcode_extractor == lp_opcode_write_middle || opcode_extractor == lp_opcode_write_only) begin 
                        ongoing_transmission <= 1'b1; 
                        current_qpn <= qpn_extractor; 
                    end 

                end else begin 
                    // Incoming chunk is part of a larger, already started transmission 
                    
                end 
            end
        end 

    end 


endmodule 