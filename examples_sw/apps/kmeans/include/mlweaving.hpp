// Copyright 2018 Zeke Wang, ETH, Zurich
// Author : Zeke Wang (zeke.wang [at] inf.ethz.ch) 
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.

#ifndef MLWEAVING_H
#define MLWEAVING_H


// This file is mainly about how to compress the dataset into MLWeaving layout and 
// to get data (char or short) out of MLWeaving layout, 

#include "string.h"
#include <immintrin.h>
#include <tgmath.h>
#include <omp.h>
#include <numeric> 
#include <x86intrin.h>
#include <pthread.h>

// #include <boost/math/common_factor.hpp>

#define BITS_OF_CL      512
#define NUM_PIPE       	32

typedef long long int vec __attribute__((vector_size(32),aligned(32)));
typedef float vec_flt __attribute__((vector_size(32),aligned(32)));

uint32_t compute_num_cl_tuples(uint32_t numSamples, uint32_t numFeatures)
{
	uint32_t NUM_BLOCK = ceil((float)numSamples/(float)NUM_PIPE) * numFeatures;
	uint32_t NUM_BLOCK_COLUMN = BITS_OF_CL/NUM_PIPE;
	uint32_t num_cl_tuples = ceil((float)NUM_BLOCK / (float)NUM_BLOCK_COLUMN) * 32;
	printf("num_cl_tuples:%d\n", num_cl_tuples);
	return num_cl_tuples;
}

void convert_float_to_fix(float* float_src, uint32_t* fix_src, uint32_t numSamples, uint32_t numFeatures)
{
	uint32_t scale = 1;
	for (int i = 0; i < numSamples; ++i)
	{
		for (int j = 0; j < numFeatures; ++j)
		{
			fix_src[i*numFeatures+j] = (uint32_t) (float_src[i*numFeatures+j]*scale);
			// printf("%d ", fix_src[i*numFeatures+j] );
		}
		// printf("\n");
	}
}


//This function performs weaving on the input data array: src.
//Input : src  (dense, unsigned int) 	
//Output: dest (in MLWeaving)
void mlweaving_on_sample(uint32_t *dest, uint32_t *src, uint32_t numSamples, uint32_t numFeatures) 
{
	printf("start MLWeaving\n");
	uint32_t address_index = 0;
	uint32_t sample_idx = 0;
	uint32_t feature_idx = 0;
	uint32_t NUM_BLOCK = ceil((float)numSamples/(float)NUM_PIPE) * numFeatures;
	uint32_t NUM_BLOCK_COLUMN = BITS_OF_CL/NUM_PIPE;
	uint32_t NUM_BLOCK_ROW = ceil( (float)NUM_BLOCK / (float)NUM_BLOCK_COLUMN );
	printf("NUM_BLOCK:%d, NUM_BLOCK_COLUMN:%d, NUM_BLOCK_ROW:%d\n", NUM_BLOCK, NUM_BLOCK_COLUMN, NUM_BLOCK_ROW);

	///Do the bitWeaving to the training data...

	//each block row contains #BITS_OF_CL/NUM_PIPE blocks, which is 512 bits
	for (uint32_t i = 0; i < NUM_BLOCK; i+=NUM_BLOCK_COLUMN)
	{   
		uint32_t blocks_in_cl = ( (i+NUM_BLOCK_COLUMN)<NUM_BLOCK )? NUM_BLOCK_COLUMN:(NUM_BLOCK-i); 

		uint32_t tmp_buffer[512] = {0};

		for (int j = 0; j < blocks_in_cl; ++j)
		{
			uint32_t sample_in_block = ((sample_idx + NUM_PIPE)<numSamples) ? NUM_PIPE : (numSamples - sample_idx);

			//1: initilization off tmp buffer..
			for (int k = 0; k < sample_in_block; k++)
			{
				tmp_buffer[ j*NUM_PIPE+k] = src[ (k+sample_idx)*numFeatures + feature_idx ];
				// printf("addr:%d, %x ", (k+sample_idx)*numFeatures + feature_idx, tmp_buffer[ j*NUM_PIPE+k]);
			}
		//	printf("\n");
			if (feature_idx == numFeatures -1)
			{
				feature_idx = 0;
				sample_idx = sample_idx + sample_in_block;
			}
			else
				feature_idx++;
		}

		//2: focus on the data from index:
		for (int k = 0; k < 32; k++)
		{	
			uint32_t result_buffer[16] = {0};
			//2.1: re-order the data according to the bit-level...
			for (int m = 0; m < 512; m++)
			{
				result_buffer[m>>5] = result_buffer[m>>5] | ((tmp_buffer[m] >>31)<<(m&31));
				tmp_buffer[m]       = tmp_buffer[m] << 1;				
			}
		    //2.2: store the bit-level result back to the memory...
			dest[address_index++] = result_buffer[0];
			dest[address_index++] = result_buffer[1];
			dest[address_index++] = result_buffer[2];
			dest[address_index++] = result_buffer[3];
			dest[address_index++] = result_buffer[4];
			dest[address_index++] = result_buffer[5];
			dest[address_index++] = result_buffer[6];
			dest[address_index++] = result_buffer[7];
			dest[address_index++] = result_buffer[8];
			dest[address_index++] = result_buffer[9];
			dest[address_index++] = result_buffer[10];
			dest[address_index++] = result_buffer[11];
			dest[address_index++] = result_buffer[12];
			dest[address_index++] = result_buffer[13];
			dest[address_index++] = result_buffer[14];
			dest[address_index++] = result_buffer[15];
		}
	}
	printf("finished ml weaving\n");
}

// This function retrives one single sample feature from the mlweaving layout with address: src. 
// dest: destination 
// src : address of mlweaving array
void retrieve_from_mlweaving(uint32_t* dest, uint32_t *mlweaving_src, uint32_t sample_idx, uint32_t feature_idx, uint32_t numFeatures, uint32_t numSamples) 
{	
	// printf("retrieve from MLWeaving\n");
	uint32_t NUM_BLOCK = ceil((float)numSamples/(float)NUM_PIPE) * numFeatures;
	uint32_t NUM_BLOCK_COLUMN = BITS_OF_CL/NUM_PIPE;
	uint32_t NUM_BLOCK_ROW = ceil( (float)NUM_BLOCK / (float)NUM_BLOCK_COLUMN );

	uint32_t block_idx = (sample_idx/NUM_PIPE)*numFeatures + feature_idx;
	uint32_t cl_offset = (block_idx/NUM_BLOCK_COLUMN)*32;
	uint32_t bit_offset_cl = (block_idx % NUM_BLOCK_COLUMN)*NUM_PIPE + sample_idx % NUM_PIPE;
	uint32_t int_offset_cl = bit_offset_cl/32;
	uint32_t addr_offset = cl_offset*16 + int_offset_cl;
	uint32_t bit_offset_int = bit_offset_cl % 32;
	// printf("block_idx:%d, cl_offset:%d, bit_offset_cl:%d, int_offset_cl:%d,bit_offset_int:%d\n", block_idx, cl_offset, bit_offset_cl,int_offset_cl,bit_offset_int);

	uint32_t result=0;
	// printf("MSB:");
	for (int i = 0; i < 32; ++i)
	{
		uint32_t bit = ((mlweaving_src[addr_offset+16*i] & (1<<bit_offset_int)) >> bit_offset_int);
		// printf("%d", bit);
		result |= ((mlweaving_src[addr_offset+16*i] & (1<<bit_offset_int)) >> bit_offset_int) << (31-i);
	}
	// printf(" retrieve result:%d\n", result);
	dest[sample_idx*numFeatures+feature_idx] = result;
}

void print_weaving (uint32_t num_cl_tuples, uint32_t* weaving_dest)
{
	printf("print weaving\n");
	for (int i = 0; i < num_cl_tuples; ++i)
	{
		for (int j = 0; j < 16; ++j)
		{
			printf("%u ", weaving_dest[i*16+j]);
		}
		printf("\n");
	}
}

void compare_results_ml_weaving(uint32_t* fix_src, uint32_t* retrieve_dest, uint32_t numFeatures, uint32_t numSamples )
{
	uint32_t num_error = 0;
	for (int i = 0; i < numSamples; ++i)
	{
		for (int j = 0; j < numFeatures; ++j)
		{
			if (fix_src[i*numFeatures+j] != retrieve_dest[i*numFeatures+j])
			{
	//			printf("sample:%d, feature:%d, fix_src:%x, retrieve_dest:%x\n", i,j,fix_src[i*numFeatures+j],retrieve_dest[i*numFeatures+j]);
				num_error++;
			}		
		}
	}
	if (num_error==0)
	{
		printf("All comparisons correct\n");
	}
	else 
		printf("Comparison not correct with num_error:%d\n", num_error);
}

void test_ml_weaving(float* float_src ,uint32_t numSamples, uint32_t numFeatures)
{
	printf("start test_ml_weaving\n");
	uint32_t num_cl_tuples = compute_num_cl_tuples( numSamples,  numFeatures);
	uint32_t* weaving_dest = NULL;
	int status =posix_memalign((void**)&weaving_dest, 64, num_cl_tuples*sizeof(uint32_t)*16);
	memset(weaving_dest,0,num_cl_tuples*sizeof(uint32_t)*16);

	uint32_t* fix_src = NULL;
	status=posix_memalign((void**)&fix_src, 64, sizeof(uint32_t)*numFeatures*numSamples);
	convert_float_to_fix(float_src, fix_src, numSamples, numFeatures);

	mlweaving_on_sample(weaving_dest, fix_src, numSamples, numFeatures);
	// print_weaving(num_cl_tuples, weaving_dest);

	uint32_t* retrieve_dest = NULL;
	status=posix_memalign((void**)&retrieve_dest, 64, sizeof(uint32_t)*numFeatures*numSamples);

	printf("start retrieve_dest\n");
	for (int i = 0; i < numSamples ; ++i)
	{
		for (int j = 0; j < numFeatures; ++j)
		{
			retrieve_from_mlweaving(retrieve_dest, weaving_dest, i, j, numFeatures, numSamples);
			// printf("%d ", retrieve_dest[i*numFeatures+j] );
		}
		// printf("\n");
	}
	compare_results_ml_weaving(fix_src, retrieve_dest, numFeatures, numSamples);
}

struct thread_arg
{
	int *dest; 
	int *src;
	uint32_t numSamples;
	uint32_t numFeatures;
	int threadID;
};

#endif