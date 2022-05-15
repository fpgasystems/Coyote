module percentage(
    input   wire            clk,
    input   wire            rst_n,

    input   wire  [511:0]   predicates_line,
    input   wire            predicates_valid,
    input   wire            predicates_last,
    output  wire            predicates_in_ready,

    input   wire  [511:0]   data_line,
    input   wire            data_valid,
    input   wire            data_last,
    output  wire            data_in_ready,
    
    output  reg   [39:0]    total_sum,
    output  reg   [39:0]    selected_sum,
    output  reg   [31:0]    selected_count, 
    output  reg             output_valid       
);

reg [511:0] pred_line;
reg pred_valid;
reg pred_last;
reg part;

reg [511:0] d_line;
reg d_valid;
reg d_last;

wire [255:0] pred_half;

wire [15:0] notequal_0;

wire matches_valid;
wire [5:0] matches_count;

wire [35:0] full_accm;
wire full_accm_valid;
wire full_accm_last;

wire [35:0] selective_accm;
wire selective_accm_valid;

///////////////////////////////////////////////////////////////////////
/// Keep Predicate line for two successive data lines
///////////////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (~rst_n) begin
        // reset
        pred_line  <= 0;
        pred_valid <= 0;
        pred_last  <= 0;
    end
    else if(~pred_valid | (part & d_valid)) begin
        pred_line  <= predicates_line;
        pred_valid <= predicates_valid;
        pred_last  <= predicates_last;
    end
end

always @(posedge clk) begin
  if (~rst_n) begin
    part <= 0;
  end
  else begin
    case (part) 
      1'b0: begin
        if(pred_valid & d_valid) begin
          part <= 1'b1;
        end
      end
      1'b1: begin
        if(d_valid) begin
          part <= 1'b0;
        end
      end
    endcase
  end
end
//
assign predicates_in_ready = ~pred_valid | (part & d_valid);
///////////////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
    if (~rst_n) begin
        // reset
        d_line  <= 0;
        d_valid <= 0;
        d_last  <= 0;
    end
    else if(~d_valid | pred_valid) begin
        d_line  <= data_line;
        d_valid <= data_valid;
        d_last  <= data_last;
    end
end
assign data_in_ready       = (~d_valid | pred_valid);
/////////////////////////////////////////////////////////////////////////////////////

////////////////////////// test_count module instance ///
assign pred_half = (part)? pred_line[511:256] : pred_line[255:0];
// count non zero predicates
genvar i;

generate
  for(i = 0; i < 16; i = i + 1) begin
    assign notequal_0[i] = ~(pred_half[(i+1)*16-1 : i*16] == 0);
  end 
endgenerate

onesCounterC4 onesCounterC4
(
  .clk            (clk),
  .rst_n          (rst_n),

  .data_in_valid  (d_valid & pred_valid),
  .data_in        ({16'b0, notequal_0}),

  .count_valid    (matches_valid),
  .count          (matches_count)
);


always@(posedge clk) begin
  if(~rst_n) begin
    selected_count <= 0;
  end
  else if(matches_valid) begin
    selected_count <= selected_count + matches_count;
  end
end

//////

reduction_tree reduce_full(

  .clk                (clk),
    .rst_n              (rst_n),
    .stall_pipeline     (1'b0),

    .data_line          (d_line),
    .data_mask          (16'hFFFF),
    .data_valid         (d_valid & pred_valid),
    .data_last          (d_last),
    .reduce_result      (full_accm), 
    .result_valid       (full_accm_valid),
    .result_last        (full_accm_last)                 
  );

always @(posedge clk) begin
  if (~rst_n) begin
    // reset
    total_sum    <= 0;
    output_valid <= 0;
  end
  else if (full_accm_valid) begin
    total_sum    <= total_sum + {4'b0, full_accm};
    output_valid <= full_accm_last;
  end
end

reduction_tree reduce_selective(

  .clk                (clk),
    .rst_n              (rst_n),
    .stall_pipeline     (1'b0),

    .data_line          (d_line),
    .data_mask          (notequal_0),
    .data_valid         (d_valid & pred_valid),
    .data_last          (1'b0),
    .reduce_result      (selective_accm), 
    .result_valid       (selective_accm_valid),
    .result_last        ()             
  );

always @(posedge clk) begin
  if (~rst_n) begin
    // reset
    selected_sum <= 0;
  end
  else if (selective_accm_valid) begin
    selected_sum <= selected_sum + {4'b0, selective_accm};
  end
end


endmodule 