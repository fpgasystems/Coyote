//---------------------------------------------------------------------------
//--  Copyright 2015 - 2017 Systems Group, ETH Zurich
//-- 
//--  This hardware module is free software: you can redistribute it and/or
//--  modify it under the terms of the GNU General Public License as published
//--  by the Free Software Foundation, either version 3 of the License, or
//--  (at your option) any later version.
//-- 
//--  This program is distributed in the hope that it will be useful,
//--  but WITHOUT ANY WARRANTY; without even the implied warranty of
//--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//--  GNU General Public License for more details.
//-- 
//--  You should have received a copy of the GNU General Public License
//--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//---------------------------------------------------------------------------

module rem_top_ff #(parameter CHAR_COUNT=16, DELIMITER=0, STATE_COUNT=8)
    (
    clk,
    rst, //active high
    softRst,
  
    input_valid,
    input_data,

    input_ready,

    output_valid,
    output_match,    
    output_index    
    );


  input clk;
  input rst;
  input softRst;
  
  input input_valid;
  input [511:0] input_data;

  output reg input_ready;

  output reg output_valid;
  output reg output_match; 
  output reg [15:0] output_index; 

  reg scan_mode;
    
  reg input_wasvalid;
  reg input_wasready;
  reg input_hasdata;
  reg [511:0] input_datareg;

  reg config_valid; 
  reg [CHAR_COUNT*8-1:0] config_chars;
  reg [CHAR_COUNT/2-1:0] config_ranges;
  reg [CHAR_COUNT-1:0] config_conds;

  reg [STATE_COUNT*(CHAR_COUNT)-1:0] config_state_pred;
  reg [STATE_COUNT*STATE_COUNT-1:0] config_state_act;  

  reg restart;
  reg wait_new;
  reg wait_conf;
  
  wire pred_valid;
  wire [CHAR_COUNT-1:0] pred_bits;
  wire [15:0] pred_index;
  wire pred_last;

  reg need_purge;

  reg pred_valid_D;
  reg pred_last_D;
  reg [15:0] pred_index_D;

  reg [STATE_COUNT*(CHAR_COUNT)-1:0] state_pred_masks;
  reg [STATE_COUNT*STATE_COUNT-1:0] state_act_masks;

  wire [STATE_COUNT-1:0] state_match_bits;
  wire [STATE_COUNT-1:0] state_inact_bits;
  wire [STATE_COUNT-1:0] state_outact_bits;

  reg [STATE_COUNT*4-1:0] state_inact_delays;

  reg [STATE_COUNT-1:0] always_activated;
  reg [STATE_COUNT-1:0] state_act_sticky;

  reg [15:0] string_length;
  reg [7:0] length_remaining ;
  reg [5:0] byte_addr;

  reg waiting_pred;

  reg dec_valid;
  reg dec_last;
  reg [7:0] dec_char;

  reg rstBuf;

  localparam STATE_ACT_SIZE = (STATE_COUNT*STATE_COUNT % 8 ==0) ? STATE_COUNT*STATE_COUNT : STATE_COUNT*STATE_COUNT+8-(STATE_COUNT*STATE_COUNT%8);


  rem_decoder  #(
  		.CHAR_COUNT(CHAR_COUNT),
  		.DELIMITER(DELIMITER)
  	) decoder_inst (
  		.clk(clk),
        .rst(rstBuf),
        .config_valid(config_valid),
        .config_chars(config_chars),
        .config_ranges(config_ranges),
        .config_conds(config_conds),
        .input_valid(dec_valid),
        .input_last(dec_last),
        .input_char(dec_char),
        .index_rewind(wait_new),
		.output_valid(pred_valid),
		.output_data(pred_bits),
		.output_index(pred_index),
		.output_last(pred_last)
  	);


  	genvar X;
  	generate
  		for (X=0; X<STATE_COUNT; X=X+1)
  		begin: gen_states
  			rem_onestate onestate_inst (	
				.clk(clk),
				.rst(rstBuf | wait_new),        

        .is_sticky(state_act_sticky),

        .delay_valid(config_valid),
        .delay_cycles(state_inact_delays[X*4 +: 4]),

				.pred_valid(pred_valid),
				.pred_match(state_match_bits[X]),

				.act_input(state_inact_bits[X]),
				.act_output(state_outact_bits[X])
			);

  			assign state_match_bits[X] = ((state_pred_masks[(X+1)*(CHAR_COUNT)-1:X*(CHAR_COUNT)] & pred_bits) == 0 && state_pred_masks[(X+1)*(CHAR_COUNT)-1:X*(CHAR_COUNT)]!=0) ? 0 : 1;

  			assign state_inact_bits[X] = ((state_act_masks[(X+1)*STATE_COUNT-1:X*STATE_COUNT] & state_outact_bits) != 0) ? 1 : always_activated[X];
  		end  		
  	endgenerate

    integer ind;

  	always @(posedge clk) begin

  		pred_valid_D <= pred_valid;
  		pred_last_D <= pred_last;
      pred_index_D <= pred_index;

      rstBuf <= rst;

  		if (rst) begin

  			output_valid <= 0;  			  			  		
        always_activated <= 0;
        string_length <= 0;

        wait_new <= 1;
        wait_conf <= 1;
        restart <= 0;
        need_purge <= 0;

        input_ready <= 1;

        config_valid <= 0;
        dec_valid <= 0;
        dec_last <= 0;

        input_wasready <= input_ready;
        input_wasvalid <= input_valid;

        input_hasdata <= 0;

        state_inact_delays <= 0;

        waiting_pred <= 0;
        
        scan_mode <= 0;

  		end
  		else begin

        if (restart) begin
          wait_conf <= 1 & (~scan_mode);
          wait_new <= 1;
          restart <= 0;
        end

        if (softRst) begin
          wait_conf <= 1;
          wait_new <= 1;
          restart <= 0;
        end        

        input_wasvalid <= input_valid;
        input_wasready <= input_ready;

        output_valid <= 0;
        config_valid <= 0;
        dec_valid <= 0;
        dec_last <= 0;

        if (input_valid==1) begin
          input_ready <= 0;          
        end  			

        input_hasdata <= input_ready==1 ? 0 : input_hasdata;

        if (input_ready && input_valid) begin
          input_datareg <= input_data;
          input_hasdata <= 1;
          
          $display("INPUT %x", input_data);
        end

        if (input_hasdata==1 && wait_conf==1) begin
          config_valid <= 1;
          config_chars <= input_datareg[CHAR_COUNT*8-1:0];
          config_ranges <= input_datareg[CHAR_COUNT/2 + CHAR_COUNT*8-1 : CHAR_COUNT*8];
          config_conds <= input_datareg[CHAR_COUNT-1+CHAR_COUNT/2 + CHAR_COUNT*8:CHAR_COUNT/2 + CHAR_COUNT*8];
          config_state_pred <= input_datareg[STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8-1:CHAR_COUNT/2 + CHAR_COUNT*8+CHAR_COUNT];
          config_state_act <= input_datareg[STATE_COUNT*STATE_COUNT+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8-1:STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8];

          state_pred_masks <= input_datareg[STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8-1:CHAR_COUNT/2 + CHAR_COUNT*8+CHAR_COUNT];
          state_act_masks <= input_datareg[STATE_COUNT*STATE_COUNT+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8-1:STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8];

          state_inact_delays <= input_datareg[STATE_COUNT*4-1+STATE_ACT_SIZE+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8 : STATE_ACT_SIZE+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8];
          state_act_sticky <= input_datareg[STATE_COUNT-1+STATE_COUNT*4+STATE_ACT_SIZE+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8 : STATE_COUNT*4+STATE_ACT_SIZE+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8];

   
          for (ind=0; ind<STATE_COUNT; ind=ind+1) begin
            always_activated[ind]=0;
            if (input_datareg[(ind)*STATE_COUNT+STATE_COUNT*CHAR_COUNT+CHAR_COUNT+CHAR_COUNT/2 + CHAR_COUNT*8 +: STATE_COUNT]==0) always_activated[ind]=1;
          end

          wait_conf <= 0;
          input_ready <= 1;
          
          scan_mode <= input_datareg[511];
        end

        if (restart==0 && wait_conf==0) begin

          if (!input_ready && input_hasdata==1 && wait_new==1) begin
            byte_addr <= 2;
            string_length <= input_datareg[15:0];
            length_remaining <= (input_datareg[15:0]+63)/64;

            wait_new <= 0;
            if (input_datareg[15:0]==0) begin
              wait_new <=1;
              input_ready <= 1;
            end
          end

          if (!input_ready && input_hasdata==1 && wait_new==0) begin

            if (byte_addr<=63) begin
              dec_valid <= 1;
              dec_char <= input_datareg[byte_addr[5:0]*8 +: 8];
              byte_addr <= byte_addr+1;            
              if (byte_addr==63 && length_remaining==1) begin
                dec_last <= 1;
              end else begin
                dec_last <= 0;
              end
              
            end

            if (byte_addr==63 && length_remaining>1) begin
              byte_addr <= 0;
              input_ready <= 1;
              length_remaining <= length_remaining-1;            
            end
            else if (byte_addr==63 && length_remaining==1 && !need_purge) begin
              byte_addr <= 0;
              input_hasdata <= 0;
              waiting_pred <= 1;
              length_remaining <= 0;
            end

            if (need_purge==1) begin
              if (length_remaining>1) begin
                byte_addr <= 64;
                length_remaining <= length_remaining-1;
                input_ready <= 1;
              end 
              else begin
                byte_addr <= 0;
                restart <= 1;
                input_ready <= 1;  
                need_purge <= 0;
              end
            end

          end


    			if (!need_purge && !wait_new && pred_valid_D==1 && (state_outact_bits[STATE_COUNT-1]==1 || pred_last_D==1)) begin            
    				output_valid <= 1;
    				output_match <= state_outact_bits[STATE_COUNT-1]==1;
    				output_index <= pred_index_D;

            if (!waiting_pred) begin
              need_purge<=1;
            end
            else begin
              waiting_pred <= 0;
              byte_addr <= 0;
              restart <= 1;
              input_ready <= 1;  
              need_purge <= 0;
            end
    			end

          if (!input_hasdata && output_valid==1 && waiting_pred==1) begin
            waiting_pred <= 0;
            byte_addr <= 0;
            restart <= 1;
            input_ready <= 1;  
            need_purge <= 0;
          end

          if (!need_purge && waiting_pred==1 && pred_valid_D==0 && length_remaining==0) begin
            output_valid <= 1;
            output_match <= 0;
            output_index <= 0;

            waiting_pred <= 0;
            byte_addr <= 0;
            restart <= 1;
            input_ready <= 1;  
            need_purge <= 0;
          end
        end
  			
  		end
  	end


endmodule