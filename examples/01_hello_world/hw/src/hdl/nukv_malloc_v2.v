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

`default_nettype none

module nukv_Malloc #(
	parameter MEMORY_WIDTH = 512,
	parameter BLOCKSIZE = 64, //B,
	parameter REQSIZE = 1, //B
    parameter MAX_MEMORY_SIZE = 24,
	parameter CLASS_COUNT = 8,
    parameter SUPPORT_SCANS = 1,
    parameter IS_SIM = 0
	)
    (
	// Clock
	input wire         clk,
	input wire         rst,

	input  wire [15:0] req_data,
	input wire 			req_valid,
	output reg 		req_ready,

	output reg [31:0] malloc_pointer,
	output reg 	   malloc_valid,
	output reg 	   malloc_failed,
	input wire 	       malloc_ready,
	
	input wire [31:0] free_pointer,
	input wire [15:0] free_size,
	input wire 	       free_valid,
	output reg 		   free_ready,
    input wire         free_wipe,

    input wire         scan_start,

    output reg         is_scanning,
    output reg[31:0]   scan_numlines,

    output reg         scan_valid,
    output reg [31:0]  scan_addr,
    output reg [7:0]   scan_cnt,
    input wire         scan_ready,

    input wire          scan_pause,


	output reg [31:0] p_rdcmd_data,
	output reg         p_rdcmd_valid,
	input  wire         p_rdcmd_ready,

	input wire [MEMORY_WIDTH-1:0]  p_rd_data,
	input wire         p_rd_valid,
	output  reg         p_rd_ready,	

	output reg [MEMORY_WIDTH-1:0] p_wr_data,
	output reg         p_wr_valid,
	input  wire         p_wr_ready,

	output reg [31:0] p_wrcmd_data,
	output reg         p_wrcmd_valid,
	input  wire         p_wrcmd_ready,


	output reg [31:0] b_rdcmd_data,
    output reg [7:0]  b_rdcmd_cnt,
 	output reg         b_rdcmd_valid,
	input  wire         b_rdcmd_ready,

	input wire [MEMORY_WIDTH-1:0]  b_rd_data,
	input wire         b_rd_valid,
	output  reg         b_rd_ready,	

	output reg [MEMORY_WIDTH-1:0] b_wr_data,
	output reg         b_wr_valid,
	input  wire         b_wr_ready,

	output reg [31:0] b_wrcmd_data,
	output reg         b_wrcmd_valid,
	input  wire         b_wrcmd_ready,

    output reg error_memory,
    output reg[7:0] error_state,

    output reg[31:0] stat_size

	// memory interface...
	
);


    localparam [3:0]	
    ST_ALLOC_IDLE   = 0,
    ST_ALLOC_DECIDECLASS = 1,
    ST_ALLOC_POPFIFO = 2,
	ST_ALLOC_REFILL = 3,
	ST_ALLOC_PUSHREMAINDER  = 4,
    ST_ALLOC_FETCHSCANBITMAP = 10,
    ST_ALLOC_NEWSCANBITMAP = 11,  
    ST_ALLOC_PUSHSCANBITMAP  = 12,
    ST_ALLOC_SCAN = 13;
	reg [3:0] alloc_state;

	localparam [3:0]
	ST_FREE_INIT = 0,
	ST_FREE_IDLE = 1,
    ST_FREE_FETCHBITMAP = 2,
    ST_FREE_NEWBITMAP = 3,	    
    ST_FREE_FREEDPAGE = 4,
    ST_FREE_FREEDPARTIAL = 5,
    ST_FREE_PUSHBITMAP  = 6,        
	ST_FREE_SPILLTOMEMORY = 7,
    ST_FREE_SCAN_FETCHBITMAP = 10,
    ST_FREE_SCAN_NEWBITMAP = 11,
    ST_FREE_SCAN_PUSHBITMAP = 12;
	reg [3:0] free_state;


    localparam integer
        CLASS1 = 1,
        CLASS2 = 2,
        CLASS3 = 4,
        CLASS4 = 8,
        CLASS5 = 16,
        CLASS6 = 32,
        CLASS7 = 64;

    localparam integer REFILL_BUFF_BITS = (IS_SIM==0 ? 6 : 4);    

    reg[31:0] tail_pointer[0:CLASS_COUNT-1];
    reg[31:0] head_pointer[0:CLASS_COUNT-1];
    reg[31:0] upper_bound[0:CLASS_COUNT-1];

    localparam[31:0] ADDRESS_BITS = (IS_SIM==0) ? MAX_MEMORY_SIZE : 18; 
    localparam[31:0] MAX_POINTER_LINES = 2**(ADDRESS_BITS-9-3); 
    localparam[31:0] BITMAP_OFFSET_IN_MEM = CLASS_COUNT*(MAX_POINTER_LINES); 
    localparam[31:0] SCANBM_OFFSET_IN_MEM =  (SUPPORT_SCANS==0) ? BITMAP_OFFSET_IN_MEM : (BITMAP_OFFSET_IN_MEM + (2**ADDRESS_BITS ) / (BLOCKSIZE*32'd8)); 
    localparam[31:0] DATA_OFFSET_IN_MEM = SCANBM_OFFSET_IN_MEM + (2**ADDRESS_BITS ) / (BLOCKSIZE*32'd8); 

     reg[63:0] queuein[0:CLASS_COUNT-1];
     wire[63:0] queueout[0:CLASS_COUNT-1];

     reg[CLASS_COUNT-1:0] queuepush;
     wire[CLASS_COUNT-1:0] queuepop;
     reg[CLASS_COUNT-1:0] queueread;
     wire[CLASS_COUNT-1:0] queueready;
     wire[CLASS_COUNT-1:0] queuevalid;

     reg[CLASS_COUNT-1:0] queue_mutex;

     reg[7:0] spill_cnt;
     reg[3:0] spill_class;

     reg[63:0] newpointer;

     genvar gv;
     
     generate
     for (gv=0; gv<CLASS_COUNT; gv=gv+1) begin: fifos
     
         nukv_fifogen #(
            .DATA_SIZE(64),
            .ADDR_BITS(REFILL_BUFF_BITS)
        ) fifo_pointers (
            .clk(clk),
            .rst(rst),
    
            .s_axis_tdata(queuein[gv]),
            .s_axis_tvalid(queuepush[gv]),
            .s_axis_tready(queueready[gv]),
    
            .m_axis_tdata(queueout[gv]),
            .m_axis_tvalid(queuevalid[gv]),
            .m_axis_tready(queuepop[gv])
        );
     end
     endgenerate

    reg[9:0] refill_req_cnt;
    reg[9:0] refill_answ_cnt;

    reg[MEMORY_WIDTH-1:0] bitvector;

    reg [31:0] needfetch;

    reg[15:0] neededsize;

    reg[3:0] in_class;
    reg[3:0] chosen_class;
    
    reg[63:0] poppedpointer;
    reg[31:0] poppedaddrminus;

    reg[63:0] freedpoint;
    reg[31:0] freedaddrminus;

    integer i;

    reg[31:0] write_addr;
    reg[31:0] point_addr;
    integer x;

    reg[3:0] f_class;
    reg[15:0] f_size;
    reg[MEMORY_WIDTH-1:0] f_mask;
    reg[15:0] empty_begin;
    reg[15:0] empty_last;

    reg[MEMORY_WIDTH-1:0] future_bitmap;
    
    reg f_choose;
    reg have_large_pointers;

    reg[31:0] aux_sizeleft;
    reg[31:0] aux_offset;


    reg[511:0] future_scan_bitmap;
    
    reg[511:0] b_rd_reg;

    reg[31:0] scan_issued_cnt;
    reg[31:0] scan_processed_cnt;
    reg[9:0] scan_word_idx;
    reg[31:0] scan_limit;
    
    reg[511:0] scan_f_mask;

    reg[31:0] scan_base_addr;

    reg[31:0] lastscan_b_rdcmd;

    reg[31:0] lastfree_b_rdcmd;
    reg[31:0] lastfreescan_b_rdcmd;

    genvar gx;
    generate
    for (gx=0; gx<CLASS_COUNT; gx=gx+1) begin: pops
        assign queuepop[gx] = (gx==spill_class && free_state == ST_FREE_SPILLTOMEMORY) ? (p_wrcmd_ready & p_wr_ready) : queueread[gx];
    end
    endgenerate

    reg[3:0] additional_error;


    // process for the allocator
    always @(posedge clk) begin
    	if (rst) begin
    		// reset
    		p_rdcmd_valid <= 0;
    		p_rd_ready <= 0;
    		
            queueread <= 0;   
            queuepush <= 0; 		

    		malloc_valid <= 0;
    		malloc_failed <= 0;

            needfetch <= 32'hFFFF;

            req_ready <= 1;

            alloc_state <= ST_ALLOC_IDLE;

            is_scanning <= 0;
            scan_numlines <= 0;

            scan_valid <= 0;

            error_memory <= 0;

            error_state <= 0;
            additional_error <= 0;

            p_rdcmd_data <= 0;
            p_wrcmd_data <= 0;

    	end
    	else begin

            if (error_memory==1) begin
                error_memory <= 0;
                additional_error <= 0;
            end

            error_state <= {additional_error[0], free_state[2:0], alloc_state};

            if (SUPPORT_SCANS==1 && scan_valid==1 && scan_ready==1) begin
                scan_numlines <= scan_numlines + scan_cnt;
                scan_valid <= 0;
            end

    		p_rd_ready <= 0;

    		if (p_rdcmd_valid==1 && p_rdcmd_ready==1) begin
    			p_rdcmd_valid <= 0;
    		end

    		if (malloc_valid==1 && malloc_ready==1) begin
    			malloc_valid <= 0;
    			malloc_failed <= 0;
    		end

            queueread <= 0;


            for (i=0; i<CLASS_COUNT; i=i+1) begin
                if (queuepush[i]==1 && queueready[i]==1) begin
                    queuepush[i] <= 0; 
                end
            end

    		case (alloc_state)

    		ST_ALLOC_IDLE : begin

                if (SUPPORT_SCANS==1 && scan_start==1) begin

                    alloc_state <= ST_ALLOC_SCAN;
                    scan_issued_cnt <= 0;
                    scan_processed_cnt <= 0;       
                    scan_word_idx <= 0;
                    scan_limit <= DATA_OFFSET_IN_MEM - SCANBM_OFFSET_IN_MEM;
                    scan_base_addr <= DATA_OFFSET_IN_MEM;

                    is_scanning <= 1;
                    scan_numlines <= 0;
                    req_ready <= 0; 


                end else 
    			if (req_valid==1 && req_ready==1) begin
    				
    				in_class <= (req_data <= CLASS1*BLOCKSIZE) ? 1 : (req_data<=CLASS2*BLOCKSIZE) ? 2 : (req_data<=CLASS3*BLOCKSIZE) ? 3 : (req_data<=CLASS4*BLOCKSIZE) ? 4 : (req_data<=CLASS5*BLOCKSIZE) ? 5 : (req_data<=CLASS6*BLOCKSIZE) ? 6 : (req_data<=CLASS7*BLOCKSIZE) ? 7 :0;

                    neededsize <= (req_data <= CLASS1*BLOCKSIZE) ? CLASS1 : (req_data<=CLASS2*BLOCKSIZE) ? CLASS2 : (req_data<=CLASS3*BLOCKSIZE) ? CLASS3 : (req_data<=CLASS4*BLOCKSIZE) ? CLASS4 : (req_data<=CLASS5*BLOCKSIZE) ? CLASS5 : (req_data<=CLASS6*BLOCKSIZE) ? CLASS6 : (req_data<=CLASS7*BLOCKSIZE) ? CLASS7 : 0;

                    have_large_pointers <= (queuevalid[0]==1 || (head_pointer[0]!=tail_pointer[0])) ? 1 : 0;

                    alloc_state <= ST_ALLOC_DECIDECLASS;

                    req_ready <= 0;
    			end
    		end

            ST_ALLOC_DECIDECLASS : begin
                chosen_class <= (queuevalid[in_class]==1 || (head_pointer[in_class]!=tail_pointer[in_class])) ? in_class : 0;

                if (free_state!=ST_FREE_INIT) begin
                    alloc_state <= ST_ALLOC_POPFIFO;
                end
            end

            ST_ALLOC_POPFIFO : begin
                if (free_state!=ST_FREE_FREEDPAGE && free_state!=ST_FREE_FREEDPARTIAL && queue_mutex[chosen_class]==0 && queue_mutex[in_class]==0) begin

                    queue_mutex[chosen_class] <= 1;
                    queue_mutex[in_class] <= 1;

                    if (queuevalid[chosen_class]==1) begin
                        queueread[chosen_class] <= 1;

                        malloc_valid <= 1;
                        malloc_failed <= 0;
                        malloc_pointer <= queueout[chosen_class][31:0];

                        if (queueout[chosen_class][31:0]<DATA_OFFSET_IN_MEM) begin
                            error_memory <= 1;
                            additional_error <= 0;
                        end

                        poppedpointer <= queueout[chosen_class][63:0];
                        poppedaddrminus <= queueout[chosen_class][31:0] - DATA_OFFSET_IN_MEM;

                        alloc_state <= ST_ALLOC_PUSHREMAINDER; 


                    end else begin
                        alloc_state <= ST_ALLOC_REFILL;

                        p_rdcmd_data <= tail_pointer[chosen_class];

                        if (tail_pointer[chosen_class]>=BITMAP_OFFSET_IN_MEM) begin
                            error_memory <= 1;
                            additional_error <= 1;
                        end
                       
                        poppedpointer <= 0;

                        refill_req_cnt <= 2**REFILL_BUFF_BITS;
                        refill_answ_cnt = 0;
                    end
                    
                end
            end

            ST_ALLOC_PUSHREMAINDER: begin
                
                if (poppedpointer[63:32]>=2*neededsize) begin
                    queuein[in_class] <= {poppedpointer[63:32]-neededsize, poppedpointer[31:0]+neededsize};
                    queuepush[in_class] <= 1;
                end

                if (SUPPORT_SCANS==0) begin
                    alloc_state <= ST_ALLOC_IDLE;
                    req_ready <= 1;
                end else begin

                    scan_f_mask <= 512'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;                
                                    
                    case (in_class)         

                        1 : scan_f_mask[poppedaddrminus[8:0] +: CLASS1] <= 0; 
                        2 : scan_f_mask[poppedaddrminus[8:0] +: CLASS2] <= 0; 
                        3 : scan_f_mask[poppedaddrminus[8:0] +: CLASS3] <= 0; 
                        4 : scan_f_mask[poppedaddrminus[8:0] +: CLASS4] <= 0;
                        5 : scan_f_mask[poppedaddrminus[8:0] +: CLASS5] <= 0;
                        6 : scan_f_mask[poppedaddrminus[8:0] +: CLASS6] <= 0;
                        7 : scan_f_mask[poppedaddrminus[8:0] +: CLASS7] <= 0;
                          

                    endcase



                    alloc_state <= ST_ALLOC_FETCHSCANBITMAP;
                    
                end

                queue_mutex[chosen_class] <= 0;
                queue_mutex[in_class] <= 0;
                
             end


            ST_ALLOC_FETCHSCANBITMAP : begin

                if (free_state!=ST_FREE_NEWBITMAP && free_state!=ST_FREE_PUSHBITMAP) begin
                    alloc_state <= ST_ALLOC_NEWSCANBITMAP;
                    b_rdcmd_data <= SCANBM_OFFSET_IN_MEM + (poppedaddrminus)/512;
                    b_rdcmd_cnt <= 1;
                    b_rdcmd_valid <= 1; 
                    lastscan_b_rdcmd <= SCANBM_OFFSET_IN_MEM + (poppedaddrminus)/512;
                end
            end



            ST_ALLOC_NEWSCANBITMAP : begin
                if (b_rd_valid==1 && b_rd_ready==0) begin
                    b_rd_ready <= 1;
                    future_scan_bitmap <= scan_f_mask & b_rd_data;
                    
                    alloc_state <= ST_ALLOC_PUSHSCANBITMAP;
                    
                end
            end


            ST_ALLOC_PUSHSCANBITMAP: begin                                                                       
                
                if (b_wrcmd_ready==1 && b_wr_ready==1) begin
                                            
                    b_wr_data <= future_scan_bitmap;
                    b_wr_valid <= 1;

                    b_wrcmd_data <= lastscan_b_rdcmd;

                    if (lastscan_b_rdcmd<SCANBM_OFFSET_IN_MEM || lastscan_b_rdcmd>=DATA_OFFSET_IN_MEM) begin
                        error_memory <= 1;
                        additional_error <= 0;
                    end

                    b_wrcmd_valid <= 1;

                    alloc_state <= ST_ALLOC_IDLE;
                    req_ready <= 1;
                end

            end
                               

            ST_ALLOC_REFILL : begin

                if (p_rdcmd_ready==1 && p_rdcmd_valid==0 && refill_req_cnt>0) begin

                    refill_req_cnt <= refill_req_cnt-8;
                    tail_pointer[chosen_class] <= tail_pointer[chosen_class]+1;
                    
                    if (tail_pointer[chosen_class]+1==upper_bound[chosen_class])begin
                    
                        if (chosen_class>0) begin
                            tail_pointer[chosen_class] <= upper_bound[chosen_class-1];
                        end else begin
                            tail_pointer[chosen_class] <= 0;
                        end
                    end
                    p_rdcmd_data <= tail_pointer[chosen_class];
                    p_rdcmd_valid <= 1;

                    if (tail_pointer[chosen_class] >= BITMAP_OFFSET_IN_MEM) begin
                        error_memory <= 1;
                        additional_error <= 0;
                    end
                    
                end

                queuepush[chosen_class] <= 0;


                if (p_rd_valid==1 && p_rd_ready==0 && queueready[chosen_class]==1) begin

                    refill_answ_cnt <= refill_answ_cnt+1;

                    queuein[chosen_class] <= p_rd_data[refill_answ_cnt[2:0]*64 +: 64];

                    queuepush[chosen_class] <= 1;

                    if (p_rd_data[refill_answ_cnt[2:0]*64 +: 32] >= 2**MAX_MEMORY_SIZE || p_rd_data[refill_answ_cnt[2:0]*64 +: 32]<DATA_OFFSET_IN_MEM) begin

                        error_memory <= 1;
                        additional_error <= 1;

                        queuepush[chosen_class] <= 0;

                    end else if (poppedpointer[31:0]==0) begin

                        queuepush[chosen_class] <= 0;

                        malloc_valid <= 1;
                        malloc_failed <= 0;
                        malloc_pointer <= p_rd_data[refill_answ_cnt[2:0]*64 +: 32];

                        poppedpointer <= p_rd_data[refill_answ_cnt[2:0]*64 +: 64];
                        poppedaddrminus <= p_rd_data[refill_answ_cnt[2:0]*64 +: 32];

                    end
                    
                    if (refill_answ_cnt[2:0]==7) begin
                        p_rd_ready <= 1;
                    end

                    if (refill_answ_cnt==2**REFILL_BUFF_BITS-1) begin

                        alloc_state <= ST_ALLOC_PUSHREMAINDER; 
                        poppedaddrminus <= poppedaddrminus- DATA_OFFSET_IN_MEM;

                    end                        

                        



                end

                
                
            end


            ST_ALLOC_SCAN : begin                 
                
                if (scan_ready==1 && scan_pause==0) begin                
                    
                    if (scan_issued_cnt<scan_limit && (scan_issued_cnt-scan_processed_cnt<24) && b_rdcmd_ready==1 && b_rdcmd_valid==0) begin
                        b_rdcmd_valid <= 1;
                        b_rdcmd_data <= SCANBM_OFFSET_IN_MEM+scan_issued_cnt;
                        b_rdcmd_cnt <= 4;
                        scan_issued_cnt <= scan_issued_cnt+4;
                    end                

                    if (b_rd_valid==1 && b_rd_ready== 0 && scan_ready==1 && scan_processed_cnt<scan_limit) begin

                        if (scan_word_idx<512) begin
                        
                            if (scan_word_idx == 0) begin
                            
                                b_rd_reg <= {1'b1, b_rd_data[511:1]};
                                                                                 
                                if (b_rd_data == 512'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin
                                    scan_word_idx <= 0;   
                                    b_rd_ready <= 1;
                                    scan_processed_cnt <= scan_processed_cnt+1;
                                    scan_word_idx <= 0;
                                    scan_base_addr <= 512+scan_processed_cnt*512+DATA_OFFSET_IN_MEM;              

                                end else if (b_rd_data[63:0]== 64'hFFFFFFFFFFFFFFFF) begin
                                    scan_word_idx <= scan_word_idx+64;
                                    b_rd_reg <= {64'hFFFFFFFFFFFFFFFF, b_rd_data[511:64]};              
                                end else if (b_rd_data[7:0]== 8'hFF) begin
                                    scan_word_idx <= scan_word_idx+8;
                                    b_rd_reg <= {8'hFF, b_rd_data[511:8]};
                                end else if (b_rd_data[0] == 1'b1) begin
                                    scan_word_idx <= scan_word_idx+1;
                                end else if (b_rd_data[0] == 1'b0) begin
                                    
                                    scan_valid <= 1;
                                    scan_addr <= scan_word_idx+scan_base_addr;
                                        
                                    if (b_rd_data[7:0] == 0) begin
                                        scan_cnt <= 8;
                                        scan_word_idx <= scan_word_idx+8;
                                        b_rd_reg <= {8'hFF, b_rd_data[511:8]};
                                    end else begin
                                        scan_cnt <= 1;
                                        scan_word_idx <= scan_word_idx+1;
                                    end
                                end
                                
                            end else begin
                            //scan_word_idx > 0
                                b_rd_reg <= {1'b1, b_rd_reg[511:1]};
                                                                             
                                if (b_rd_reg == 512'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin

                                    b_rd_ready <= 1;
                                    scan_processed_cnt <= scan_processed_cnt+1;
                                    scan_word_idx <= 0;
                                    scan_base_addr <= 512+scan_processed_cnt*512+DATA_OFFSET_IN_MEM;  

                                end else if (b_rd_data[127:0]== 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) begin                                
                                    scan_word_idx <= scan_word_idx+128;
                                    b_rd_reg <= {128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, b_rd_reg[511:128]};                                       
                                end else if (b_rd_data[63:0]== 64'hFFFFFFFFFFFFFFFF) begin
                                    scan_word_idx <= scan_word_idx+64;
                                    b_rd_reg <= {64'hFFFFFFFFFFFFFFFF, b_rd_reg[511:64]};                               
                                end else if (b_rd_reg[7:0]== 8'hFF) begin
                                    scan_word_idx <= scan_word_idx+8;
                                    b_rd_reg <= {8'hFF, b_rd_reg[511:8]};
                                end else if (b_rd_reg[0] == 1'b1) begin
                                    scan_word_idx <= scan_word_idx+1;
                                end else if (b_rd_reg[0] == 1'b0) begin
                                    
                                    scan_valid <= 1;
                                    scan_addr <= scan_word_idx+scan_base_addr;
                                    

                                   /* if (b_rd_reg[15:0] == 0) begin
                                        scan_cnt <= 16;
                                        scan_word_idx <= scan_word_idx+16;
                                        b_rd_reg <= {16'hFFFF, b_rd_reg[511:16]};                                    
                                    end else     */
                                    if (b_rd_reg[7:0] == 0) begin
                                        scan_cnt <= 8;
                                        scan_word_idx <= scan_word_idx+8;
                                        b_rd_reg <= {8'hFF, b_rd_reg[511:8]};                                                                       
                                    end else begin
                                        scan_cnt <= 1;
                                        scan_word_idx <= scan_word_idx+1;
                                    end
                                end                            
                            
                            end
                            
                            
                        end else begin
                            b_rd_ready <= 1;
                            scan_processed_cnt <= scan_processed_cnt+1;
                            scan_word_idx <= 0;
                            scan_base_addr <= 512+scan_processed_cnt*512+DATA_OFFSET_IN_MEM;
                        end

                    end                

                end

                if (scan_issued_cnt>=scan_limit && scan_processed_cnt>=scan_limit) begin
                    alloc_state <= ST_ALLOC_IDLE;
                    is_scanning <= 0;             
                    req_ready <= 1;       
                end

            end

    		endcase

    		
    	end

        //-----------------------------------------------------------------------------------
        //-----------------------------------------------------------------------------------
        //----FREE---------------------------------------------------------------------------
        //-----------------------------------------------------------------------------------
        //-----------------------------------------------------------------------------------
   
    	if (rst) begin
    		
    		free_state <= ST_FREE_IDLE;
    		write_addr <= BITMAP_OFFSET_IN_MEM;
    		point_addr <= 0;
            free_ready <= 1;

            for (i=0; i<CLASS_COUNT; i=i+1) begin
                tail_pointer[i] <= i*(MAX_POINTER_LINES);
                head_pointer[i] <= i*(MAX_POINTER_LINES);
                upper_bound[i] <= (i+1)*(MAX_POINTER_LINES);

                queue_mutex[i] <= 0;
            end

            p_wrcmd_valid <= 0;
            p_wr_valid <= 0;

            b_rdcmd_valid <= 0;

            b_wr_valid <= 0;
            b_wrcmd_valid <= 0;

            b_rd_ready <= 0;
    		
    	end
    	else begin

            

            if (b_rd_ready==1) begin
                b_rd_ready <= 0;
            end

    		if (b_wr_valid==1 && b_wr_ready==1) begin
    			b_wr_valid <= 0;
    		end

			if (b_wrcmd_valid==1 && b_wrcmd_ready==1) begin
    			b_wrcmd_valid <= 0;
    		end  

    		if (p_wr_valid==1 && p_wr_ready==1) begin
    			p_wr_valid <= 0;
    		end

			if (p_wrcmd_valid==1 && p_wrcmd_ready==1) begin
    			p_wrcmd_valid <= 0;
    		end   

            if (b_rdcmd_valid==1 && b_rdcmd_ready==1) begin
                b_rdcmd_valid <= 0;
            end

           		

            if (SUPPORT_SCANS==0) begin
                scan_valid <= 0;
                scan_addr <= 0;
                scan_cnt <= 0;
            end

    		case (free_state) 

    			ST_FREE_INIT : begin
    				
    				if (b_wrcmd_ready==1 && b_wr_ready==1 && b_wrcmd_valid==0 && b_wr_valid==0 && write_addr<DATA_OFFSET_IN_MEM) begin

    					b_wrcmd_valid <= 1;
    					b_wrcmd_data <= write_addr;
    					write_addr <= write_addr+1;

    					b_wr_data <= 512'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;                    					
                        b_wr_valid <= 1;


                        if (write_addr<BITMAP_OFFSET_IN_MEM) begin
                            error_memory <= 1;
                            additional_error <= 0;
                        end
    				end 

    				if (write_addr==DATA_OFFSET_IN_MEM)  begin 
    					
    					if (p_wrcmd_ready==1 && p_wr_ready==1 && p_wrcmd_valid==0 && p_wr_valid==0 && point_addr<MAX_POINTER_LINES) begin 
    						p_wrcmd_valid <=1;
    						p_wrcmd_data <= point_addr;

                            if (point_addr>=MAX_POINTER_LINES) begin
                                error_memory <= 1;
                                additional_error <= 1;
                            end



    						p_wr_valid <= 1;

    						for (x=0; x<8; x=x+1) begin
    							p_wr_data[x*64 +: 32] <= ((point_addr*8+x)*MEMORY_WIDTH)+DATA_OFFSET_IN_MEM; 
                                p_wr_data[x*64+32 +: 32] <= 512; 
    						end

                            point_addr <= point_addr+1;

                            head_pointer[0] <= head_pointer[0] + 1;
                           
    						
    					end


                        if (  point_addr==MAX_POINTER_LINES) begin                         
                            
                            free_state <= ST_FREE_IDLE;
                            free_ready <= 1;

                        end

    				end

                    // TODO if SUPPORT_SCANS

    			end

                ST_FREE_IDLE: begin
                    
                    if (free_valid==1 && free_ready==1 && free_wipe==1) begin
                        free_state <= ST_FREE_INIT;
                        write_addr <= BITMAP_OFFSET_IN_MEM;
                        free_ready <= 0;
                    end

                    if (free_valid==1 && free_ready==1 && free_wipe==0) begin

                        freedpoint <= free_pointer;
                        freedaddrminus <= free_pointer[31:0] - DATA_OFFSET_IN_MEM;

                        f_class <= (free_size <= CLASS1*BLOCKSIZE) ? 1 : (free_size<=CLASS2*BLOCKSIZE) ? 2 : (free_size<=CLASS3*BLOCKSIZE) ? 3 : (free_size<=CLASS4*BLOCKSIZE) ? 4 : 0;
                        f_size <= (free_size <= CLASS1*BLOCKSIZE) ? CLASS1 : (free_size<=CLASS2*BLOCKSIZE) ? CLASS2 : (free_size<=CLASS3*BLOCKSIZE) ? CLASS3: (free_size<=CLASS4*BLOCKSIZE) ? CLASS4 : 0;

                                           

                       


                        free_state <= ST_FREE_FETCHBITMAP;
                        free_ready <= 0;
                        empty_begin <= 0;
                        empty_last <= 0;

                    end                 

                end

                ST_FREE_FETCHBITMAP: begin

                    if (SUPPORT_SCANS==0 || (alloc_state!=ST_ALLOC_FETCHSCANBITMAP && alloc_state!=ST_ALLOC_NEWSCANBITMAP && alloc_state!=ST_ALLOC_PUSHSCANBITMAP)) begin

                        f_mask <= 512'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;                
                                        
                        case (f_size)         

                            1 : f_mask[freedaddrminus[8:0] +: 1] <= 0; 
                            2 : f_mask[freedaddrminus[8:0] +: 2] <= 0; 
                            4 : f_mask[freedaddrminus[8:0] +: 4] <= 0; 
                            8 : f_mask[freedaddrminus[8:0] +: 8] <= 0; 
                            16 : f_mask[freedaddrminus[8:0] +: 16] <= 0; 
                            32 : f_mask[freedaddrminus[8:0] +: 32] <= 0; 

                        endcase                             


                        free_state <= SUPPORT_SCANS==1 ? ST_FREE_SCAN_FETCHBITMAP : ST_FREE_NEWBITMAP;

                        // free some memory
                        b_rdcmd_data <= BITMAP_OFFSET_IN_MEM + (freedaddrminus)/512;
                        lastfree_b_rdcmd <= BITMAP_OFFSET_IN_MEM + (freedaddrminus)/512;
                        b_rdcmd_cnt <= 1;
                        b_rdcmd_valid <= 1;                                    

                    end

                end




                ST_FREE_NEWBITMAP : begin
                    if (b_rd_valid==1 && b_rd_ready==0) begin
                        b_rd_ready <= 1;
                        future_bitmap <= f_mask & b_rd_data;
                        
                        if ((f_mask & b_rd_data) == 0) begin
                            free_state <= ST_FREE_FREEDPAGE;
                        end else if (head_pointer[f_class]-tail_pointer[f_class] > (IS_SIM==0 ? MAX_POINTER_LINES/4 : 2)) begin
                            free_state <= ST_FREE_PUSHBITMAP;
                        end else begin
                            free_state <= ST_FREE_FREEDPARTIAL;
                        end
                        
                    end
                end


                ST_FREE_PUSHBITMAP: begin                                                                       
                    
                    if (b_wrcmd_ready==1 && b_wr_ready==1) begin
                                                
                        b_wr_data <= future_bitmap;
                        b_wr_valid <= 1;

                        b_wrcmd_data <= lastfree_b_rdcmd;
                        b_wrcmd_valid <= 1;

                        if (lastfree_b_rdcmd<BITMAP_OFFSET_IN_MEM || lastfree_b_rdcmd>=SCANBM_OFFSET_IN_MEM) begin
                            error_memory <= 1;
                            additional_error <= 0;
                        end

                        free_state <= SUPPORT_SCANS==1 ? ST_FREE_SCAN_NEWBITMAP : ST_FREE_IDLE;
                        free_ready<= SUPPORT_SCANS==1 ? 0 : 1;

                    end

                end

                ST_FREE_FREEDPAGE: begin

                    if (queue_mutex[0]==0) begin

                        queue_mutex[0] <= 1;

                        future_bitmap <= ~future_bitmap;
                        if (queueready[0]==1) begin
                            queuein[0] <= {32'h200,freedpoint[31:9],9'h0};                            
                            queuepush[0] <= 1;

                            free_state <= SUPPORT_SCANS==1 ? ST_FREE_SCAN_NEWBITMAP : ST_FREE_IDLE;
                            queue_mutex[0] <= 0;
                            free_ready <= 1;

                        end else begin
                            spill_cnt <= 64;
                            free_state <= ST_FREE_SPILLTOMEMORY;
                            newpointer <= {32'h200,freedpoint[31:9],9'h0};
                            spill_class <= 0;
                        end

                    end

                end

                ST_FREE_SPILLTOMEMORY: begin
                    if (spill_cnt>0 && p_wr_ready==1 && p_wrcmd_ready==1 && queuevalid[spill_class]==1 && queuepop[spill_class]==1) begin
                        
                        p_wr_data[spill_cnt[2:0]*64 +: 64] <= queueout[spill_class];
                        spill_cnt <= spill_cnt-1;

                        if (spill_cnt[2:0]==1) begin
                            p_wr_valid <= 1;

                            p_wrcmd_valid <= 1;
                            p_wrcmd_data <= head_pointer[spill_class]+1;

                            if (head_pointer[spill_class]+1>=BITMAP_OFFSET_IN_MEM) begin
                                error_memory <= 1;
                                additional_error <= 0;
                            end

                        end
                        
                    end

                    if (spill_cnt==0) begin
                        queuein[spill_class] <= newpointer;
                        queuepush[spill_class] <= 1;
                        free_state <= SUPPORT_SCANS==1 ? ST_FREE_SCAN_NEWBITMAP : ST_FREE_IDLE;
                        free_ready <= 1;
                        queue_mutex[spill_class] <= 0;
                    end
                end

                ST_FREE_FREEDPARTIAL : begin
                    
                    if (queue_mutex[f_class]==0) begin

                        queue_mutex[f_class] <= 1;

                        future_bitmap <= future_bitmap | ~f_mask;

                        if (queueready[f_class]==1) begin                        
                            queuein[f_class] <= freedpoint;
                            queuepush[f_class] <= 1;

                            free_state <= SUPPORT_SCANS==1 ? ST_FREE_SCAN_NEWBITMAP : ST_FREE_IDLE;
                            queue_mutex[f_class] <= 0;
                            free_ready <= 1;

                        end else begin
                            spill_cnt <= 8;
                            free_state <= ST_FREE_SPILLTOMEMORY;
                            newpointer <= freedpoint;
                            spill_class <= f_class;
                        end

                    end

                end


                ST_FREE_SCAN_FETCHBITMAP: begin

                    if (b_rdcmd_ready==1) begin
                        // free some memory
                        b_rdcmd_data <= SCANBM_OFFSET_IN_MEM + (freedaddrminus)/512;
                        lastfreescan_b_rdcmd <= SCANBM_OFFSET_IN_MEM + (freedaddrminus)/512;
                        b_rdcmd_cnt <= 1;
                        b_rdcmd_valid <= 1; 


                        free_state <= ST_FREE_NEWBITMAP;                                   
                    end



                end

                ST_FREE_SCAN_NEWBITMAP : begin
                    if (b_rd_valid==1 && b_rd_ready==0) begin
                        b_rd_ready <= 1;
                        future_bitmap <= ~f_mask | b_rd_data;
                        
                        free_state <= ST_FREE_SCAN_PUSHBITMAP;                        
                        
                    end
                end


                ST_FREE_SCAN_PUSHBITMAP: begin                                                                       
                    
                    if (b_wrcmd_ready==1 && b_wr_ready==1) begin
                                                
                        b_wr_data <= future_bitmap;
                        b_wr_valid <= 1;

                        b_wrcmd_data <= lastfreescan_b_rdcmd;
                        b_wrcmd_valid <= 1;

                        if (lastfree_b_rdcmd<BITMAP_OFFSET_IN_MEM || lastfree_b_rdcmd>=SCANBM_OFFSET_IN_MEM) begin
                            error_memory <= 1;
                            additional_error <= 0;
                        end

                        free_state <= ST_FREE_IDLE;
                        free_ready<= 1;

                    end

                end


    		endcase
    		
    	end
    end

    reg[47:0] stat_allocated;
    reg[47:0] stat_freed;

    reg[31:0] stat_compute;

    always @(posedge clk) begin  
        if (rst || (free_valid==1 && free_ready==1 && free_wipe==1)) begin
            stat_allocated <= 0;
            stat_freed <= 0;
        end else begin
            if (free_ready==1 && free_valid==1) begin
                stat_freed <= stat_freed+free_size;
            end

            if (req_valid==1 && req_ready==1) begin
                stat_allocated <= stat_allocated + req_data;
            end

            stat_compute <= stat_allocated - stat_freed;
        end

        stat_size <= stat_compute;        
    end    

    
endmodule


`default_nettype wire