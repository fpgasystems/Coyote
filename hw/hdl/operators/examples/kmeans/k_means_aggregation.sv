import kmeansTypes::*;

module k_means_aggregation
(
  input wire clk,    // Clock
  input wire rst_n,  // Asynchronous reset active low

  input wire                           start_operator,

  input wire [MAX_DEPTH_BITS:0]        data_dim, //input the actual dimension of the data
  input wire [NUM_CLUSTER_BITS:0]      num_cluster, //input the actual number of cluster

  //interface with pipelines
  // output wire                       agg_ready,
  // input wire [NUM_PIPELINE-1:0]     accu_finish,

  input wire [63:0]                 agg_data,
  input wire                        agg_valid,

  //interface with the divider
  output reg [63:0]                 div_sum,
  output reg [63:0]                 div_count,
  output reg                        div_valid,
  output reg                        div_last_dim,
  output reg                        div_last,

  output reg [63:0]                 sse,
  output reg                        sse_valid,
  output wire                       sse_converge,

  output reg [7:0][31:0]           k_means_aggregation_debug_cnt

);


  //sum FIFO signal
  wire sum_fifo_we, sum_fifo_re, sum_fifo_valid,sum_fifo_empty, sum_fifo_full;
  wire [63:0] sum_fifo_dout, sum_fifo_din; 

  //count FIFO signal
  wire count_fifo_we, count_fifo_re, count_fifo_valid,count_fifo_empty, count_fifo_full;
  wire [63:0] count_fifo_dout, count_fifo_din; 

  reg [63:0] data_cnt;

  reg [63:0] previous_sse;

  reg [16:0] dim_cnt;
  reg [16:0] cluster_cnt;


  // reg agg_ready_reg; 
  // reg [NUM_PIPELINE-1:0] accu_finish_reg;

  reg rst_n_reg;
  
  //fifo will not be full
  // assign agg_ready = agg_ready_reg;

  always @ (posedge clk) begin
    rst_n_reg <= rst_n;

    // if(~rst_n_reg) begin

    //   agg_ready_reg <= 1'b0;
    //   accu_finish_reg <= '0;
    // end
    // else begin
    //   accu_finish_reg <= accu_finish; 
    //   agg_ready_reg <= (&accu_finish_reg);
    // end
  end

//----------------------register the agg input---------------------//
reg [63:0]    agg_data_reg1, agg_data_reg2;
reg           agg_valid_reg1,agg_valid_reg2;

always @ (posedge clk) begin
  agg_data_reg1 <= agg_data;
  agg_data_reg2 <= agg_data_reg1;

  if(~rst_n_reg) begin
    agg_valid_reg1 <= 1'b0;
    agg_valid_reg2 <= 1'b0;
  end
  else begin
    agg_valid_reg1 <= agg_valid;
    agg_valid_reg2 <= agg_valid_reg1;
  end
end
//------------------------------------------------------------------//
  
//set fifo depth such that it will not overflow
quick_fifo #(.FIFO_WIDTH(64), .FIFO_DEPTH_BITS(9))
  sum_fifo
  (
  .clk,
  .reset_n(rst_n_reg),
  .we(sum_fifo_we),
  .din(sum_fifo_din),
  .re(sum_fifo_re),
  .valid(sum_fifo_valid),
  .dout(sum_fifo_dout),
  .count(),
  .empty(sum_fifo_empty),
  .full(sum_fifo_full),
  .almostfull());

  assign sum_fifo_din = agg_data_reg2;
  // assign sum_fifo_we = agg_valid_reg2 & (data_cnt < num_cluster*data_dim);
  assign sum_fifo_we = agg_valid_reg2 & (num_cluster <= data_cnt) & ( data_cnt < num_cluster*data_dim + num_cluster );
  assign sum_fifo_re = sum_fifo_valid & count_fifo_valid;


  quick_fifo #(.FIFO_WIDTH(64), .FIFO_DEPTH_BITS(NUM_CLUSTER_BITS+1))
  count_fifo
  (
  .clk,
  .reset_n(rst_n_reg),
  .we(count_fifo_we),
  .din(count_fifo_din),
  .re(count_fifo_re),
  .valid(count_fifo_valid),
  .dout(count_fifo_dout),
  .count(),
  .empty(count_fifo_empty),
  .full(count_fifo_full),
  .almostfull()
    );

  assign count_fifo_din = agg_data_reg2;
  // assign count_fifo_we = agg_valid_reg2 & ( num_cluster*data_dim <= data_cnt ) & ( data_cnt < num_cluster*data_dim + num_cluster );
  assign count_fifo_we = agg_valid_reg2 & ( data_cnt < num_cluster );
  assign count_fifo_re = count_fifo_valid & sum_fifo_valid & (dim_cnt == data_dim-1);

  always @ (posedge clk) begin
    if(~rst_n_reg) begin
      data_cnt <= '0;
      sse <= '0;
      sse_valid <= '0;
      previous_sse <= '0;
      dim_cnt <= '0;
      cluster_cnt <= '0;
    end
    else begin
      //multiplex input to different fifos
      if((data_cnt == num_cluster * data_dim + num_cluster) & agg_valid_reg2) begin
        data_cnt <= '0;
      end
      else if(agg_valid_reg2) begin
        data_cnt <= data_cnt + 1'b1;
      end

      //collect sse
      if((data_cnt == num_cluster * data_dim + num_cluster) & agg_valid_reg2) begin
        sse <= agg_data_reg2;
        previous_sse <= sse;
      end

      sse_valid <= (data_cnt == num_cluster * data_dim + num_cluster) & agg_valid_reg2;

      //dimension counter to set last dim flag
      if(sum_fifo_valid & count_fifo_valid & (dim_cnt == data_dim-1)) begin
        dim_cnt <= '0;
      end
      else if(sum_fifo_valid & count_fifo_valid) begin
        dim_cnt <= dim_cnt + 1'b1;
      end

      //cluster counter combined with dimension counter to set the last flag
      if(sum_fifo_valid & count_fifo_valid & (dim_cnt == data_dim-1) & (cluster_cnt == num_cluster -1)) begin
        cluster_cnt <= '0;
      end
      else if(sum_fifo_valid & count_fifo_valid & (dim_cnt == data_dim-1)) begin
        cluster_cnt <= cluster_cnt + 1'b1;
      end

    end
  end

  //output data path
  always @ (posedge clk) begin
    if(~rst_n_reg) begin
      div_valid <= 1'b0;
    end
    else begin
      div_count <= count_fifo_dout;
      div_sum <= sum_fifo_dout;
      div_valid <= sum_fifo_valid & count_fifo_valid; 
      div_last_dim <= sum_fifo_valid & count_fifo_valid & (dim_cnt == data_dim-1);
      div_last <= sum_fifo_valid & count_fifo_valid & (dim_cnt == data_dim-1) & (cluster_cnt == num_cluster -1);
    end
  end

  

  assign sse_converge = (sse!= 0) & (previous_sse == sse);


  //debug counters
  reg [31:0] agg_input_valid_cnt;
  // reg agg_ready_flag;
  reg [15:0][15:0] received_agg_data; //don't need to reset 

  always @ (posedge clk) begin
    if(start_operator) begin
      agg_input_valid_cnt <= '0;
      // agg_ready_flag <= 1'b0;
    end
    else begin 
      if(agg_valid_reg2) begin
        agg_input_valid_cnt <= agg_input_valid_cnt + 1'b1;
      end
      // if(agg_ready_reg) begin
      //   agg_ready_flag <= 1'b1;
      // end
      if(agg_valid_reg2) begin
         received_agg_data[agg_input_valid_cnt] <= agg_data_reg2[15:0];
      end
    end

    // k_means_aggregation_debug_cnt[0] <= agg_input_valid_cnt;
    k_means_aggregation_debug_cnt[0] <= {received_agg_data[1], received_agg_data[0]};
    k_means_aggregation_debug_cnt[1] <= {received_agg_data[3], received_agg_data[2]};
    k_means_aggregation_debug_cnt[2] <= {received_agg_data[5], received_agg_data[4]};
    k_means_aggregation_debug_cnt[3] <= {received_agg_data[7], received_agg_data[6]};
    k_means_aggregation_debug_cnt[4] <= {received_agg_data[9], received_agg_data[8]};
    k_means_aggregation_debug_cnt[5] <= {received_agg_data[11], received_agg_data[10]};
    k_means_aggregation_debug_cnt[6] <= {received_agg_data[13], received_agg_data[12]};
    k_means_aggregation_debug_cnt[7] <= {received_agg_data[15], received_agg_data[14]};
  end



`define LOG_NULL
//////////////////////////////////////////////////////////////////////////////////////////////////////
//---------------------------------log file print--------------------------------------------------//
////////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef LOG_FILE
  int file;
  reg file_finished;
  initial begin
    file = $fopen("/home/harpdev/doppiodb/fpga/operators/k_means_v2/sim_log/k_means_aggregation.txt","w");

    if(file) begin 
      $display("k_means_aggregation file open successfully\n");
      $display("output to divider",);
    end
    else 
      $display("Failed to open k_means_aggregation file\n"); 
  end

  always @ (posedge clk) begin
    if(~rst_n_reg) begin

    end
    else begin
      if(div_valid & ~div_last_dim & ~div_last) begin
        $fwrite(file,"%d ",div_sum);
      end
      else if(div_valid & div_last_dim & ~div_last) begin
        $fwrite(file,"%d; count:%d\n", div_sum, div_count);
      end
      else if(div_valid & div_last_dim & div_last) begin
        $fwrite(file,"%d; count%d\nSSE:%d\n\n\n", div_sum, div_count, sse);
      end
    end
  end
`endif
////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
  

endmodule
