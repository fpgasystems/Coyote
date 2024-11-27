//////////////////////////////////////////////////////////////////////////////////
//
// Intrusion Detection Decider - receives payload and leads it to the ML-model for decision
//
//////////////////////////////////////////////////////////////////////////////////

// Import the lynxTypes to be able to reference the datatypes 
import lynxTypes::*; 

module intrusion_detection_decider(
    // Incoming clock and reset 
    input logic nclk, 
    input logic nresetn, 

    // Incoming stream of extracted payload 
    AXI4S.s s_axis_payload_rx, 

    // Incoming Meta-Information consisting of QPN and opcode 
    input logic [31:0] meta_rx_i, 

    // Incoming meta-interface for qp-establishment that allows to extract information whether DPI is selected or not for a specific flow 
    metaIntf.s s_rdma_qp_interface, 

    // Outgoing Meta-Interface: communicates combination of QPN & ML-Decision, valid and ack 
    metaIntf.m m_rdma_intrusion_decision 
);

    ////////////////////////////////////////////////////////////////////////////////
    //
    // Definition of data types
    //
    ///////////////////////////////////////////////////////////////////////////////

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
        logic incomplete; 
        logic valid; 
        logic last; 
        logic dpi_required; 
    } MetaInformation; 

    // Decision-Word, combines QPN and decision for outgoing FIFO-port 
    typedef struct packed{
        MetaQPN QPN;        // 24 Bit 
        logic acceptable;   // 1 Bit 
    } DecisionWord; 


    ///////////////////////////////////////////////////////////////////////////////
    //
    // Definition of all required registers 
    //
    //////////////////////////////////////////////////////////////////////////////

    // Side-channel pipeline of meta-information besides the ML-model 
    MetaInformation meta_pipeline[11]; 

    // Inverted Reset for sanity
    logic rst_inverted; 

    // Connections to the ML-model interfaces 
    logic mlm_ready; 
    logic mlm_idle; 
    logic mlm_done; 
    logic mlm_decision_data; 
    logic mlm_decision_valid; 
    logic mlm_start;
    DataWord mlm_input_word; 

    // Intermediate ML-decision aggregator 
    dpi_t ml_decision_aggregator;

    // Decision calculator 
    logic decision_calculator;

    // Input delay 
    DataWord input_data_delayed;
    logic input_valid_delayed;

    // Definition of a 1024-bit register memory that stores whether DPI is required for a certain flow or not. Support for up to 1024 QPs. 
    logic dpi_required[1024]; 
 

    ///////////////////////////////////////////////////////////////////////////////
    //
    // Combinatorial logic 
    //
    ///////////////////////////////////////////////////////////////////////////////

    // Reversal of the reset for my own sanity
    assign rst_inverted = ~nresetn;

    // Calculation of the final ACK / NAK decision 
    assign decision_calculator = ((meta_pipeline[10].incomplete) ? (ml_decision_aggregator.acceptable) : (ml_decision_aggregator.acceptable & (~mlm_decision_data)));

    // Bit-Reversal of the input 
    always_comb begin
        for(integer bit_index = 0; bit_index < 512; bit_index++) begin 
            mlm_input_word[bit_index] = s_axis_payload_rx.tdata[511-bit_index];
        end
    end

    ///////////////////////////////////////////////////////////////////////////////
    //
    // Integration of the ML-Decision-Model on the datapath 
    //
    //////////////////////////////////////////////////////////////////////////////

    myproject intrusion_detector_1(
        .ap_clk(nclk), 
        .ap_rst(rst_inverted), 
        .ap_start(s_axis_payload_rx.tvalid), 
        .ap_done(mlm_done), 
        .ap_idle(mlm_idle), 
        .ap_ready(mlm_ready), 
        .q_dense_input_ap_vld(s_axis_payload_rx.tvalid), 
        .q_dense_input(mlm_input_word), 
        .layer12_out(mlm_decision_data), 
        .layer12_out_ap_vld(mlm_decision_valid)
    );
    
    // ILA around the ML
    /*ila_ml_internal inst_ila_ml_internal(
        .clk(nclk), 
        .probe0(mlm_done),              // 1
        .probe1(mlm_idle),              // 1
        .probe2(mlm_ready),             // 1
        .probe3(mlm_input_word),        // 512
        .probe4(mlm_decision_data),     // 1
        .probe5(mlm_decision_valid)     // 1
    );*/
    
    ///////////////////////////////////////////////////////////////////////////////
    //
    // Sequential logic of the meta-side channel
    //
    ///////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge nclk) begin
        if(rst_inverted) begin 
            // Reset of the sidechannel-pipeline 
            for(integer pipeline_stage = 0; pipeline_stage < 11; pipeline_stage++) begin 
                meta_pipeline[pipeline_stage].QPN <= 24'b0;
                meta_pipeline[pipeline_stage].Opcode <= 8'b0;
                meta_pipeline[pipeline_stage].incomplete <= 1'b0;
                meta_pipeline[pipeline_stage].valid <= 1'b0;
                meta_pipeline[pipeline_stage].last <= 1'b0;
            end 

            // Reset of the 1024-bit register for DPI-requirements 
            dpi_required <= 1024'b0; 

        end else begin 
            // When a new QP is set up via the qp_interface, the DPI-bit is stored in the reg-file 
            dpi_required[s_rdma_qp_interface.data.qp_num] <= s_rdma_qp_interface.data.dpi_enabled; 
            
            // Activate the first stage of the pipeline if there is a valid input 
            if(s_axis_payload_rx.tvalid) begin 
                meta_pipeline[0].QPN <= meta_rx_i[31:8];
                meta_pipeline[0].Opcode <= meta_rx_i[7:0];
                meta_pipeline[0].incomplete <= ~(s_axis_payload_rx.tkeep == 64'hffffffffffffffff);
                meta_pipeline[0].valid <= s_axis_payload_rx.tvalid;
                meta_pipeline[0].last <= s_axis_payload_rx.tlast;
                meta_pipeline[0].dpi_required <= dpi_required[meta_rx_i[31:8]]; 
            end else begin 
                meta_pipeline[0].QPN <= 24'b0;
                meta_pipeline[0].Opcode <= 8'b0;
                meta_pipeline[0].incomplete <= 1'b0;
                meta_pipeline[0].valid <= 1'b0;
                meta_pipeline[0].last <= 1'b0;
                meta_pipeline[0].dpi_required <= 1'b0; 
            end 

            // Subsequent pipeline stages 
            for(integer pipeline_stage = 1; pipeline_stage < 11; pipeline_stage++) begin 
                meta_pipeline[pipeline_stage] <= meta_pipeline[pipeline_stage-1];
            end 
        end 
    end


    //////////////////////////////////////////////////////////////////////////////////////
    //
    // Sequential logic of the ML-decision-aggregator
    //
    /////////////////////////////////////////////////////////////////////////////////////

    always_ff @(posedge nclk) begin 
        if(rst_inverted) begin 
            // Reset the ML-decision aggregator 
            ml_decision_aggregator.QPN <= 24'b0;
            ml_decision_aggregator.acceptable <= 1'b1;

            // Reset the outgoing interface port 
            m_rdma_intrusion_decision.valid <= 1'b0;
            m_rdma_intrusion_decision.data <= 25'b0;
        end else begin 
            if(meta_pipeline[10].valid) begin 
                if(meta_pipeline[10].last) begin 
                    // Send out ML-decision for the whole payload-chunk 
                    m_rdma_intrusion_decision.valid <= 1'b1;
                    m_rdma_intrusion_decision.data[24:1] <= ml_decision_aggregator.QPN;
                    m_rdma_intrusion_decision.data[0] <= decision_calculator || (~meta_pipeline[10].dpi_required);  // Acceptable if either the aggregated decision says it's acceptable or it's not required at all 

                    // Reset the ml_decision_aggregator 
                    ml_decision_aggregator.QPN <= 24'b0;
                    ml_decision_aggregator.acceptable <= 1'b1;
                end else begin 
                    // Reset the ML-decision interface output 
                    m_rdma_intrusion_decision.valid <= 1'b0;
                    m_rdma_intrusion_decision.data[24:0] <= 25'b0;

                    // Concatenate the ML-output in the ml_decision_aggregator 
                    ml_decision_aggregator.QPN <= meta_pipeline[10].QPN;
                    ml_decision_aggregator.acceptable <= decision_calculator;
                end 
            end else begin 
                // Reset the ML-decision interface output 
                m_rdma_intrusion_decision.valid <= 1'b0;
                m_rdma_intrusion_decision.data[24:0] <= 25'b0;
            end 
        end 
    end 

endmodule
