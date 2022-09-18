import lynxTypes::*;

module testcount (
  input  logic          clk,
  input  logic          rst_n, 

  input  logic          clr,
  output logic          done,

  input  logic [3:0]    test_type,
  input  logic [31:0]   test_condition,
  output logic [31:0]   result_count,

  AXI4SR.s              axis_in
);

logic less_w[15:0];
logic equal_w[15:0];

logic less[15:0];
logic equal[15:0];
logic notEqual[15:0];
logic greater[15:0];
logic greaterEqual[15:0];
logic lessEqual[15:0];

reg  [15:0]  condition_test_result;

reg [31:0] temp_count;

reg data_in_valid_d1;
reg data_in_valid_d2;

reg data_in_last_d1;
reg data_in_last_d2;
reg data_in_last_d3;
reg data_in_last_d4;
reg data_in_last_d5;

wire matches_valid;
wire [5:0] matches_count;

reg [3:0] test_type_d1;
reg data_valid;
reg data_last;

localparam [2:0] 
      EQUAL           = 3'b000,
      NOT_EQUAL       = 3'b001,
      LESS_THAN       = 3'b010, 
      LESS_EQUAL      = 3'b011, 
      GREATER_THAN    = 3'b100,
      GREATER_EQUAL   = 3'b101;

/////////////////////////////////// cycle 0: buffer input signals /////////////////////////////////
always@(posedge clk) begin
  if(~rst_n) begin
    data_in_valid_d1 <= 0;
    data_in_valid_d2 <= 0;
    data_in_last_d1  <= 0;
    data_in_last_d2  <= 0;
    data_in_last_d3  <= 0;
    data_in_last_d4  <= 0;
    data_in_last_d5  <= 0;

    test_type_d1     <= 0;

    data_valid       <= 0;
    data_last        <= 0;
  end
  else begin 
    data_in_valid_d1 <= axis_in.tvalid;
    data_in_valid_d2 <= data_in_valid_d1;

    data_in_last_d1  <= axis_in.tlast;
    data_in_last_d2  <= data_in_last_d1;
    data_in_last_d3  <= data_in_last_d2;
    data_in_last_d4  <= data_in_last_d3;
    data_in_last_d5  <= data_in_last_d4;

    test_type_d1     <= test_type;

    if(matches_valid) begin 
      data_valid       <= 1'b1;
    end
    if(data_in_last_d5) begin
      data_last        <= 1'b1;
    end 
  end
end 

/////////////////////////////////// cycle 1: evaluate conditions /////////////////////////////////
// test for == and less than
generate
  genvar i;
  for(i = 0; i < 16; i = i + 1) begin
    assign less_w[i]  = (axis_in.tdata[(i+1)*32-1 : i*32] < test_condition);
    assign equal_w[i] = (axis_in.tdata[(i+1)*32-1 : i*32] == test_condition);
 
    // produce the rest of all other condition tests
    always@(posedge clk) begin 
      if( ~ rst_n ) begin 
        greater[i]      <= 0;
        greaterEqual[i] <= 0;
        lessEqual[i]    <= 0;
        notEqual[i]     <= 0;
        less[i]         <= 0;
        equal[i]        <= 0;
      end 
      else if(axis_in.tvalid) begin 
        greater[i]      <= ~less_w[i] & ~equal_w[i];
        greaterEqual[i] <= ~less_w[i];
        lessEqual[i]    <= less_w[i] | equal_w[i];
        notEqual[i]     <= ~equal_w[i];
        less[i]         <= less_w[i];
        equal[i]        <= equal_w[i];      
      end 
      else begin
        greater[i]      <= 0;
        greaterEqual[i] <= 0;
        lessEqual[i]    <= 0;
        notEqual[i]     <= 0;
        less[i]         <= 0;
        equal[i]        <= 0;
      end
    end 

    /////////////////////////////////// cycle 1: get the right condition test /////////////////////////////////
    always@(posedge clk) begin
      case(test_type_d1)
        LESS_THAN:       condition_test_result[i] <= less[i];
        LESS_EQUAL:      condition_test_result[i] <= lessEqual[i];
        GREATER_THAN:    condition_test_result[i] <= greater[i];
        GREATER_EQUAL:   condition_test_result[i] <= greaterEqual[i];
        EQUAL:           condition_test_result[i] <= equal[i];
        NOT_EQUAL:       condition_test_result[i] <= notEqual[i];
        default:         condition_test_result[i] <= 0;
      endcase 
    end
  end
endgenerate


onesCounterC3 onesCounterC3 (
  .clk            (clk),
  .rst_n          (rst_n),

  .data_in_valid  (data_in_valid_d2),
  .data_in        (condition_test_result),

  .count_valid    (matches_valid),
  .count          (matches_count)
);

always@(posedge clk) begin
  if(~rst_n) begin
    temp_count <= 0;
  end
  else begin
    if(clr)
      temp_count <= 0;
    if(matches_valid) begin
      temp_count <= temp_count + matches_count;
    end
  end
end

/////////////////////////////////// cycle 2: Assign output signals /////////////////////////////////
always @(posedge clk) begin
  if (~rst_n) begin
    // reset
    result_count <= 0;
    done <= 0;
  end
  else begin
    result_count <= temp_count;
    done <= data_last & data_valid;
  end
end 

assign axis_in.tready = 1'b1;

endmodule