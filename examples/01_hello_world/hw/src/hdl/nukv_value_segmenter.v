module nukv_Value_Segmenter #(
    parameter MEMORY_WIDTH = 512
    )
    (
    // Clock
    input wire         clk,
    input wire         rst,

    input  wire [MEMORY_WIDTH-1:0] value_data,
    input  wire         value_valid,
    output wire         value_ready,

    output wire [MEMORY_WIDTH-1:0] output_data,
    output wire         output_valid,
    output wire         output_last,
    input  wire         output_ready

);


    localparam[2:0] 
        ST_IDLE = 0,
        ST_READING = 1,
        ST_LAST = 2;

    reg[2:0] state;


    reg out_valid;
    wire out_ready;
    reg[MEMORY_WIDTH-1:0] out_data;
    reg out_last;

    wire out_b_valid;
    wire out_b_ready;
    wire[MEMORY_WIDTH-1:0] out_b_data;
    wire out_b_last;


    reg[15:0] curr_offset;
    reg[15:0] total_length;
    reg[15:0] curr_offset_p128;

  
    wire enter_ifs;

    reg readInValue;

    wire stateBasedReady = (state==ST_IDLE) ? 1 : readInValue;

    assign value_ready = (stateBasedReady & out_ready);

    reg[MEMORY_WIDTH-1:0] slice_full;
    reg slice_valid;

    integer xx;
    

    always @(posedge clk) begin
        if (rst) begin
            // reset
            state <= ST_IDLE;
            out_valid <= 0;
            out_last <= 0;
            
            readInValue <= 0;

            slice_valid <= 0;

        end
        else begin
            
            if (out_valid==1 && out_ready==1) begin
                out_valid <= 0;
                out_last <= 0;
            end

            if (slice_valid==1 && out_ready==1) begin
                slice_valid <= 0;
            end

            if (value_valid==1 && value_ready==1) begin                
                slice_full <= value_data;
                slice_valid <= 1;
            end 


            case (state)

                ST_IDLE: begin

                    //readInValue <= 1;

                    if (value_valid==1 && out_ready==1) begin
                        
                        

                        curr_offset <= 0;
                        curr_offset_p128 <= 128;
                        total_length <= value_data[15:0]*8;                     
                        state <= ST_READING;        

                        readInValue <= 1;

                        if (value_data[15:0]*8 <= 64) begin
                            state <= ST_LAST;                                
                            if (value_valid==1 && value_ready==1) begin
                               readInValue <= 0;
                            end
                        end
                    end
                end
                        

                ST_READING: begin

                    if (slice_valid==1 && out_ready==1) begin
                        curr_offset <= curr_offset+64;
                        curr_offset_p128 <= curr_offset+64+128;

                        if (curr_offset_p128>=total_length) begin
                            state <= ST_LAST;                           
                            if (value_valid==1 && value_ready==1) begin
                                readInValue <= 0;
                            end
                        end else begin
                            state <= ST_READING;
                        end

                        out_valid <= 1;
                        out_last <= 0;
                        out_data <= slice_full;
                    end

                end

                ST_LAST: begin


                    
                    if (value_valid==1 && readInValue==0) begin
                        readInValue <= 1;    
                    end else begin
                        readInValue <= 0;
                    end
                    

                    if (value_valid==1 && value_ready==1) begin
                        readInValue <= 0;
                    end


                    if (slice_valid==1 && out_ready==1) begin
                        out_valid <= 1;
                        out_last <= 1;
                        out_data <= slice_full;

                        state <= ST_IDLE;
                        readInValue <= 0;
                        
                    end
                end

            endcase         

        end
    end


    kvs_LatchedRelay #(
        .WIDTH(MEMORY_WIDTH+1)

    ) relayreg (

        .clk(clk),
        .rst(rst),
        
        .in_valid(out_valid),
        .in_ready(out_ready),
        .in_data({out_last, out_data}),

        .out_valid(output_valid),
        .out_ready(output_ready),
        .out_data({output_last, output_data})
    );    

endmodule