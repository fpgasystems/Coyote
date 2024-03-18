/*
 * Copyright 2019 - 2020 Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
 
package kmeansTypes;


parameter NUM_CLUSTER_BITS = 2;
//parameter NUM_CLUSTER = 2**NUM_CLUSTER_BITS;
parameter NUM_CLUSTER = 2;
parameter MAX_DEPTH_BITS = 9;
parameter MAX_DIM_DEPTH = 2**MAX_DEPTH_BITS;
parameter MAX_DIM_WIDTH = 32;
parameter BUFFER_DEPTH_BITS = 9;


parameter NUM_PIPELINE_BITS =4;
parameter NUM_PIPELINE = 2**NUM_PIPELINE_BITS;
parameter NUM_BANK_BITS = 5;
parameter NUM_BANK = 2**NUM_BANK_BITS;					


typedef struct packed
{
	logic [15:0] 							num_iteration;	
	logic [63:0] 							data_set_size;
	logic [MAX_DEPTH_BITS:0] 				data_dim;
	logic [31:0] 							num_cl_tuple;
	logic [57:0] 							addr_center;
	logic [57:0] 							addr_data;
	logic [57:0] 							addr_result;
	logic [31:0] 							num_cl_centroid;
	logic [7:0]								precision;
	logic [31:0]							num_cluster;
} RuntimeParam;

endpackage



