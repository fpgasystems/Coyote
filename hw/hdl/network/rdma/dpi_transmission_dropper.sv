// Module that sits on the output data stream from the HLS-stack, reads incoming data and DPI-decisions and can then either drop the payload or not 


// Import the lynxTypes to be able to reference the datatypes 
import lynxTypes::*; 

module dpi_transmission_dropper(
    // Incoming clock and reset signal 
    input logic nclk, 
    input logic nresetn, 

    // Incoming data stream from the HLS-stack 
    AXI4S.s s_axis_rdma_wr, 

    // Outgoing data stream to the user 
    AXI4S.m m_axis_rdma_wr, 

    // Incoming user commands from the HLS-stack 
    metaIntf.s s_rdma_wr_req, 

    // Outgoing user commands to the user 
    metaIntf.m m_rdma_wr_req, 

    // Incoming intrusion decision input 
    metaIntf.s s_intrusion_decision_in
); 

///////////////////////////////////////////////////////////////
//
// Definition of registers required for managing accesses
//
///////////////////////////////////////////////////////////////

// Signal-array to cache two subsequent incoming DPI-decisions 
logic dpi_decision[2]; 

// Signal to store which of the two DPI-decisions is currently active 
logic dpi_currently_active; 

// Signal to store which of the two DPI-fields to load next 
logic dpi_load_next;

// Signal to show the currently active DPI-decision 
logic current_dpi_acceptable; 

// Register stage with the prepared AXI-data signals that need to be forwarded 
logic [511:0] axis_rdma_wr_data_inter; 
logic [63:0] axis_rdma_wr_keep_inter; 
logic axis_rdma_wr_valid_inter; 
logic axis_rdma_wr_last_inter; 

// Register stage with the prepared control-signals that need to be forwarded 
logic rdma_wr_req_valid_inter; 
req_t rdma_wr_req_data_inter;


//////////////////////////////////////////////////////////////////////
//
// Combinatorial logic: Assign ready-signals 
//
/////////////////////////////////////////////////////////////////////

// ready signal will always be assigned - there's no blocking in this module 
assign m_axis_rdma_wr.tready = s_axis_rdma_wr.tready; 
assign m_rdma_wr_req.ready = s_rdma_wr_req.ready; 

// Forwarding the data interface 
assign m_rdma_wr_req.valid = rdma_wr_req_valid_inter; 
assign m_rdma_wr_req.data = rdma_wr_req_data_inter; 

// Assign the currently active dpi-acceptable signal 
assign current_dpi_acceptable = dpi_currently_active ? dpi_decision[1].acceptable : dpi_decision[0].acceptable; 


/////////////////////////////////////////////////////////////////////
//
// Sequential logic 
//
////////////////////////////////////////////////////////////////////

always_ff @(posedge nclk) begin 
    if(!nresetn) begin
        // RESET: Assign 0-values to all internal registers 
        dpi_decision[0] <= 0; 
        dpi_decision[1] <= 0; 
        dpi_currently_active <= 0; 
        dpi_load_next <= 0; 

        // RESET: Assign 0-values to all intermediate registers  
        axis_rdma_wr_data_inter <= 512'b0; 
        axis_rdma_wr_keep_inter <= 64'b0; 
        axis_rdma_wr_valid_inter <= 1'b0; 
        axis_rdma_wr_last_inter <= 1'b0; 

        rdma_wr_req_valid_inter <= 1'b0; 
        rdma_wr_req_data_inter <= 128'b0; 

    end else begin 

        // Wait for incoming DPI-decision 
        if(s_intrusion_decision_in.valid) begin 
            // Based on the load_next-signal, load the DPI-into the correct register 
            if(!dpi_load_next) begin
                dpi_decision[0] <= s_intrusion_decision_in.data.acceptable; 
            end else begin 
                dpi_decision[1] <= s_intrusion_decision_in.data.acceptable; 
            end 

            // Change the dpi_load_next so that the next DPI-decision can be stored in the other register 
            dpi_load_next <= !dpi_load_next; 
        end 

        // Wait for incoming command 
        if(s_rdma_wr_req.valid) begin 
            // Check if the command is either a WRITE or a READ_RESPONSE. Everything else doesn't need treatment here
            if(is_opcode_rd_resp(s_rdma_wr_req.data.opcode) || is_opcode_wr(s_rdma_wr_req.data.opcode)) begin 
                // Check the currenty active DPI-decision, then based on that decide whether to forward the original command or the one modified to raise an IRQ in the vFPGA 
                if(current_dpi_acceptable) begin
                    // If the current DPI-decision indicates that the packet is acceptable, just forward the command 
                    rdma_wr_req_data_inter <= s_rdma_wr_req.data;
                    rdma_wr_req_valid_inter <= s_rdma_wr_req.valid; 
                end else begin 
                    // If the current DPI-decision indicates that the packet is not acceptable, forward a modified command with an opcode to raise an IRQ next 
                    rdma_wr_req_valid_inter <= s_rdma_wr_req.valid; 

                    rdma_wr_req_data_inter.opcode <= RC_ROCE_DPI_IRQ;  // Change opcode so that it's raising an IRQ in the vFPGA
                    rdma_wr_req_data_inter.strm <= s_rdma_wr_req.data.strm; 
                    rdma_wr_req_data_inter.mode <= s_rdma_wr_req.data.mode; 
                    rdma_wr_req_data_inter.rdma <= s_rdma_wr_req.data.rdma; 
                    rdma_wr_req_data_inter.remote <= s_rdma_wr_req.data.remote; 
                    rdma_wr_req_data_inter.vfid <= s_rdma_wr_req.data.vfid; 
                    rdma_wr_req_data_inter.pid <= s_rdma_wr_req.data.pid; 
                    rdma_wr_req_data_inter.dest <= s_rdma_wr_req.data.dest; 
                    rdma_wr_req_data_inter.last <= s_rdma_wr_req.data.last; 
                    rdma_wr_req_data_inter.vaddr <= s_rdma_wr_req.data.vaddr; 
                    rdma_wr_req_data_inter.len <= s_rdma_wr_req.data.len; 
                    rdma_wr_req_data_inter.actv <= s_rdma_wr_req.data.actv; 
                    rdma_wr_req_data_inter.host <= s_rdma_wr_req.data.host; 
                    rdma_wr_req_data_inter.offs <= s_rdma_wr_req.data.offs; 
                    rdma_wr_req_data_inter.rsrvd <= s_rdma_wr_req.data.rsrvd; 
                end 

            end else begin 
                // If it's not a WRITE or READ_RESPONSE, just forward the commands on the corresponding interface 
                rdma_wr_req_data_inter <= s_rdma_wr_req.data; 
                rdma_wr_req_valid_inter <= s_rdma_wr_req.valid; 
            end 
        end else begin 
            // If there's no active command, set the intermediate register to 0 
            rdma_wr_req_data_inter <= 128'b0; 
            rdma_wr_req_valid_inter <= 1'b0; 
        end 
    end


    // Wait for incoming data 
    if(s_axis_rdma_wr.tvalid) begin
        // Check the currently active DPI-decision.
        if(current_dpi_acceptable) begin
            // If the current transmission is acceptable, just write the values in the intermediate register 
            axis_rdma_wr_data_inter <= s_axis_rdma_wr.tdata; 
            axis_rdma_wr_keep_inter <= s_axis_rdma_wr.tkeep; 
            axis_rdma_wr_last_inter <= s_axis_rdma_wr.tlast; 
            axis_rdma_wr_valid_inter <= s_axis_rdma_wr.tvalid; 
        end else begin 
            // If the current transmission is not acceptable, set the intermediate stage to 0 and thus drop the data 
            axis_rdma_wr_data_inter <= 512'b0; 
            axis_rdma_wr_keep_inter <= 64'b0; 
            axis_rdma_wr_last_inter <= 1'b0; 
            axis_rdma_wr_valid_inter <= 1'b0; 
        end 

        // If a tlast is set, switch the pointer for the current DPI-decision 
        if(s_axis_rdma_wr.tlast) begin 
            dpi_currently_active <= !dpi_currently_active; 
        end 

    end else begin 
        // If there's no active transmission right now, set the intermediate register stage to all 0
        axis_rdma_wr_data_inter <= 512'b0; 
        axis_rdma_wr_keep_inter <= 64'b0; 
        axis_rdma_wr_last_inter <= 1'b0; 
        axis_rdma_wr_valid_inter <= 1'b0; 
    end  
end 