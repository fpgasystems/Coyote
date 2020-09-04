import lynxTypes::*;

module req_reg_rtl (
	input logic 			aclk,
	input logic 			aresetn,
	
	reqIntf.s 				req_in,
	reqIntf.m 				req_out
);
	// Internal registers
    logic in_ready_C, in_ready_N;

    req_t out_req_C, out_req_N;
    logic [N_REQUEST_BITS-1:0] out_req_id_C, out_req_id_N;
    logic out_valid_C, out_valid_N;

    req_t tmp_req_C, tmp_req_N;
    logic [N_REQUEST_BITS-1:0] tmp_req_id_C, tmp_req_id_N;
    logic tmp_valid_C, tmp_valid_N;
    
    // Comb
    assign in_ready_N = req_out.ready || (!tmp_valid_C && (!out_valid_C || !req_in.valid));

    always_comb begin
        out_valid_N = out_valid_C;
        out_req_N = out_req_C;
        out_req_id_N = out_req_id_C;

        tmp_valid_N = tmp_valid_C;
        tmp_req_N = tmp_req_C;
        tmp_req_id_N = tmp_req_id_C;

        if(in_ready_C) begin
            if(req_out.ready || !out_valid_C) begin
                out_valid_N = req_in.valid;
                out_req_N = req_in.req;
                out_req_id_N = req_in.id;
            end
            else begin
                tmp_valid_N = req_in.valid;
                tmp_req_N = req_in.req;
                tmp_req_id_N = req_in.id;
            end
        end
        else if(req_out.ready) begin
            out_valid_N = tmp_valid_C;
            out_req_N = tmp_req_C;
            out_req_id_N = tmp_req_id_C;

            tmp_valid_N = 1'b0;
        end
    end

    // Reg process
    always_ff @(posedge aclk, negedge aresetn) begin
        if(~aresetn) begin
            out_valid_C <= 1'b0;
            out_req_C <= 0;
            out_req_id_C <= 0;
            tmp_valid_C <= 1'b0;
            tmp_req_C <= 0;
            tmp_req_id_C <= 0;
            in_ready_C <= 1'b0;
        end
        else begin
            out_valid_C <= out_valid_N;
            out_req_C <= out_req_N;
            out_req_id_C <= out_req_id_C;
            tmp_valid_C <= tmp_valid_N;
            tmp_req_C <= tmp_req_N;
            tmp_req_id_C <= tmp_req_id_N;
            in_ready_C <= in_ready_N;
        end
    end

	// Outputs
    assign req_in.ready = in_ready_C;

    assign req_out.valid = out_valid_C;
    assign req_out.req = out_req_C;
    assign req_out.id = out_req_id_C;

endmodule