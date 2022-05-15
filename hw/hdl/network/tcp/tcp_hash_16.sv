/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
  * All rights reserved.
  *
  * Redistribution and use in source and binary forms, with or without modification,
  * are permitted provided that the following conditions are met:
  *
  * 1. Redistributions of source code must retain the above copyright notice,
  * this list of conditions and the following disclaimer.
  * 2. Redistributions in binary form must reproduce the above copyright notice,
  * this list of conditions and the following disclaimer in the documentation
  * and/or other materials provided with the distribution.
  * 3. Neither the name of the copyright holder nor the names of its contributors
  * may be used to endorse or promote products derived from this software
  * without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  */

`timescale 1ns / 1ps

import lynxTypes::*;

/**
 * @brief   Generic hash function.
 *
 * To be used in conjunction with hdl/gen/rnd_table.cpp
 *
 *  @param N_TABLES  		Number of tables (multiple often used for cuckoo hashing)
 *	@param N_BLOCKS			Number of lookup blocks
 *	@param KEY_SIZE			Input key size
 *	@param TABLE_SIZE		Size of the hash table (output size)
 */
module tcp_hash_16 #(
	parameter integer N_TABLES = 1,
	parameter integer N_BLOCKS = 2,
    parameter integer KEY_SIZE = 16,
    parameter integer TABLE_SIZE = 8
) (
    input  logic [N_TABLES-1:0][KEY_SIZE-1:0]     	key_in,
    output logic [N_TABLES-1:0][TABLE_SIZE-1:0]   	hash_out
);

// Hash -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------------------
logic [1-1:0][2-1:0][16-1:0] hash_lup;
// Block: 0
assign hash_lup[0][0][0] = 0;
assign hash_lup[0][0][1] = 33;
assign hash_lup[0][0][2] = 193;
assign hash_lup[0][0][3] = 117;
assign hash_lup[0][0][4] = 136;
assign hash_lup[0][0][5] = 56;
assign hash_lup[0][0][6] = 12;
assign hash_lup[0][0][7] = 173;
assign hash_lup[0][0][8] = 173;
assign hash_lup[0][0][9] = 239;
assign hash_lup[0][0][10] = 98;
assign hash_lup[0][0][11] = 132;
assign hash_lup[0][0][12] = 212;
assign hash_lup[0][0][13] = 8;
assign hash_lup[0][0][14] = 13;
assign hash_lup[0][0][15] = 135;

// Block: 1
assign hash_lup[0][1][0] = 171;
assign hash_lup[0][1][1] = 1;
assign hash_lup[0][1][2] = 98;
assign hash_lup[0][1][3] = 17;
assign hash_lup[0][1][4] = 106;
assign hash_lup[0][1][5] = 175;
assign hash_lup[0][1][6] = 150;
assign hash_lup[0][1][7] = 238;
assign hash_lup[0][1][8] = 216;
assign hash_lup[0][1][9] = 134;
assign hash_lup[0][1][10] = 23;
assign hash_lup[0][1][11] = 167;
assign hash_lup[0][1][12] = 106;
assign hash_lup[0][1][13] = 179;
assign hash_lup[0][1][14] = 233;
assign hash_lup[0][1][15] = 195;

// ----------------------------------------------------------------------------------------

localparam integer ORDER = $clog2(N_BLOCKS);
localparam integer N_LUPS = KEY_SIZE / ORDER;

// Calculate hash
logic [N_TABLES-1:0][N_LUPS-1:0][TABLE_SIZE-1:0] tmp;
logic [N_TABLES-1:0][TABLE_SIZE-1:0] tmp_out;

always_comb begin : HASH_CALC_1
	for(int i = 0; i < N_TABLES; i++) begin
		for(int j = 0; j < N_LUPS; j++) begin
			tmp[i] = hash_lup[i][key_in[i][j+:ORDER]][j];
		end
	end
end

always_comb begin : HASH_CALC_2
	tmp_out = 0;
	for(int i = 0; i < N_TABLES; i++) begin
		for(int j = 0; j < N_LUPS; j++) begin
			tmp_out[i] ^= tmp[i][j];
		end
	end
end

assign hash_out = tmp_out;

endmodule // fifo