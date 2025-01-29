`timescale 1ns / 1ps

import lynxTypes::*;

// TEMPLATE

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
 
module hash #(
	parameter integer N_TABLES = 1,
	parameter integer N_BLOCKS = 2,
    parameter integer KEY_SIZE = 64,
    parameter integer TABLE_SIZE = 10
) (
    input  logic [N_TABLES-1:0][KEY_SIZE-1:0]     	key_in,
    output logic [N_TABLES-1:0][TABLE_SIZE-1:0]   	hash_out
);

`include "tabulation_table.svh"

localparam integer ORDER = $clog2(N_BLOCKS);
localparam integer N_LUPS = KEY_SIZE / ORDER;

// Calculate hash
logic [N_TABLES-1:0][N_LUPS-1:0][TABLE_SIZE-1:0] tmp;
logic [N_TABLES-1:0][TABLE_SIZE-1:0] tmp_out;

always_comb begin : HASH_CALC_1
	for(int i = 0; i < N_TABLES; i++) begin
		for(int j = 0; j < N_LUPS; j++) begin
			tmp[i][j] = hash_lup[i][key_in[i][j+:ORDER]][j];
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
