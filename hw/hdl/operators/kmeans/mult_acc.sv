import kmeansTypes::*;

module mul_accu (
    input   wire                                   clk,
    input   wire                                   rst_n,

    //-----------------------Input of model x-------.---------------------//
    input   wire  [31:0]                           x,                    

    //-----------------------Input of samples bits-------.----------------//
    input   wire                                   a_valid,   
    input   wire [31:0]                            a,
    input   wire                                   a_last_dim,

    output  wire  [63:0]                           result,  
    output  wire                                   result_valid
);


reg [53:0]    dist_euclidean;
logic [31:0]    sub;

reg a_valid_reg1, a_valid_reg2, a_last_dim_reg1, a_last_dim_reg2 ;

always_comb begin : substraction
    if(x > a) begin
        sub = x - a;
    end
    else begin
        sub = a - x;
    end
end 


//takes 2 cycle
// logic_dsp_unsigned_27x27_atom mult_and_accu(
//         .clk_i  (clk),
//         .clr    (~rst_n),
//         .ax     (sub[26:0]),
//         .ay     (sub[26:0]),
//         .accu_en(a_valid_reg2 & (~a_last_dim_reg2) ),
//         .resulta(dist_euclidean)
//         );

reg [53:0] mult_result;

always @ (posedge clk) begin
    if (~rst_n) begin
        mult_result <= '0;
    end
    else begin
        if (a_valid) begin
            mult_result <= sub[26:0] * sub[26:0];
        end
        else begin
            mult_result <= '0;
        end 
    end
end


always @ (posedge clk) begin
    if (~rst_n) begin
        dist_euclidean <= '0;
    end
    else begin
        if (a_valid_reg2 & (~a_last_dim_reg2)) begin
            dist_euclidean <= mult_result + dist_euclidean;
        end
        else begin
            dist_euclidean <= mult_result;
        end
    end
end


always @ (posedge clk) begin
    a_valid_reg1 <= a_valid;
    a_valid_reg2 <= a_valid_reg1;

    a_last_dim_reg1 <= a_last_dim;
    a_last_dim_reg2 <= a_last_dim_reg1;
end

//Output of dot product module.
    assign result        = {10'b0, dist_euclidean};      
    assign result_valid  = a_valid_reg2 & a_last_dim_reg2;  

endmodule