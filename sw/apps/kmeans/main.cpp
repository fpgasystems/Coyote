/*
 * Copyright (c) 2019, Systems Group, ETH Zurich
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


#include <string.h>
#include <vector>
#include "utils.hpp"
#include "kmeans.hpp"
#include <tgmath.h>
#include<iostream>
#include<numeric>
#include<chrono>

//#include "hw_kmeans.hpp"
#include "mlweaving.hpp"
#include "classical_kmeans.hpp"

#include "cProcess.hpp"

#define KMEANS_OP 16
#define TUPLES_PER_CACHE_LINE 16

using namespace std;
using namespace fpga;

// Coyote params
constexpr auto const targetRegion = 0;
constexpr auto const hugeAlloc = true;

// KMeans args
struct arguments
{

   uint16_t       number_of_iteration;
   uint64_t       data_set_size;
   uint32_t       number_of_cluster;
   uint32_t       data_dimension;
   uint32_t       precision;
   string         filename;
   bool           runSw;
   bool           runhw;
   // uint32_t       num_threads;
};


arguments parseArguments(int argc, char* argv[])
{
  arguments args;
  args.runhw = true;
  args.runSw = true;
  // args.num_threads=1;

  for(int i=0; i<argc; i++){
    //split space deliminated strings
    string arg_str = string(argv[i]);
    //Check for the first few characters for identifiers
    if (arg_str.substr(0, 8) == "-object=" ){
      istringstream(arg_str.substr(8)) >> args.data_set_size;
      // args.data_set_size = (args.data_set_size +63)/64*64;
      printf("object size:%lu\n", args.data_set_size);
    }
    if (arg_str.substr(0, 9) == "-cluster=" ){
        istringstream(arg_str.substr(9)) >> args.number_of_cluster;
        printf("cluster size:%d\n",args.number_of_cluster);
    }
    if (arg_str.substr(0, 5) == "-dim=" ){
        istringstream(arg_str.substr(5)) >> args.data_dimension;
        args.data_dimension = args.data_dimension;
        printf("dimension:%u\n", args.data_dimension); 
    }
    if (arg_str.substr(0, 6) == "-iter=" ){
        istringstream(arg_str.substr(6)) >> args.number_of_iteration;
        printf("iteration:%d\n", args.number_of_iteration);
    }
    if (arg_str.substr(0, 6) == "-prec=")
    {
       istringstream(arg_str.substr(6)) >> args.precision;
       printf("precision:%d\n", args.precision);
    }
    if (arg_str.substr(0, 13) == "-object_file=" ){
        args.filename = arg_str.substr(13);
        cout<<"file path:"<<args.filename<<endl;
    }
    // if (arg_str.substr(0, 8) == "-thread=" ){
    //     istringstream(arg_str.substr(8)) >> args.num_threads;
    //     args.num_threads = args.num_threads;
    //     printf("num_threads:%u\n", args.num_threads); 
    // }
  }
   return args; 
};


//Application

int main(int argc, char* argv[])
{

  arguments args = parseArguments(argc, argv);

  //parse the arguments
  uint16_t number_of_iteration = args.number_of_iteration;
  uint64_t data_set_size = args.data_set_size;
  uint32_t number_of_cluster = args.number_of_cluster;
  uint32_t data_dimension = (args.data_dimension+15)/16*16;
  uint32_t non_padding_dimension = args.data_dimension;
  printf("dimension multiple of 16: %u\n", data_dimension);
  uint32_t precision = args.precision;
  const char* filename = args.filename.c_str();
  // int NUM_THREADS = args.num_threads;

  //get number of tuples
  uint32_t number_of_tuples_center = number_of_cluster*data_dimension; //total dimensions for all centroids
  uint32_t number_of_tuples_dataset = data_set_size* data_dimension; //total dimensions for all dataset

  //number of cl of centroid
  uint32_t num_cl_centroid = ceil((float)number_of_tuples_center/ (float)TUPLES_PER_CACHE_LINE);
  //get number of cacheline for mlweaving
  uint32_t num_cl_tuple = compute_num_cl_tuples(data_set_size, data_dimension);
  printf("num_cl_tuple:%u,num_cl_centroid:%u\n",num_cl_tuple, num_cl_centroid);

  //allocate memory space
  float* addr_data = reinterpret_cast<float*>( malloc(data_dimension*data_set_size*sizeof(float)));
  memset(addr_data, 0 , data_dimension*data_set_size*sizeof(float));
  uint32_t* addr_data_unsigned = reinterpret_cast<uint32_t*>( _mm_malloc(data_dimension*data_set_size*sizeof(uint32_t), 64));

  uint32_t* addr_center = NULL;
  int status =posix_memalign((void**)&addr_center, 64, num_cl_centroid*16*sizeof(uint32_t) );
  memset(addr_center, 0 , num_cl_centroid*16*sizeof(uint32_t));

  uint32_t* low_prec_sw_center = NULL;
  status=posix_memalign((void**)&low_prec_sw_center, 64, data_dimension*number_of_cluster*sizeof(uint32_t) );
  memset(low_prec_sw_center, 0 , data_dimension*number_of_cluster*sizeof(uint32_t));

  uint32_t* low_prec_hw_center = NULL;
  status=posix_memalign((void**)&low_prec_hw_center, 64, data_dimension*number_of_cluster*sizeof(uint32_t) );
  memset(low_prec_hw_center, 0 , data_dimension*number_of_cluster*sizeof(uint32_t));

  uint32_t* addr_data_weaving = NULL;
  status=posix_memalign((void**)&addr_data_weaving, 64, num_cl_tuple*16*sizeof(uint32_t) );
  memset(addr_data_weaving, 0 , num_cl_tuple*16*sizeof(uint32_t));

  float* dr_a_min    = (float *)malloc(data_dimension*sizeof(float)); //to store the minimum value of features.....
  float* dr_a_max    = (float *)malloc(data_dimension*sizeof(float)); //to store the miaximum value of features.....

  float* denomalized_center = NULL;
  status=posix_memalign((void**)&denomalized_center, 64, data_dimension*number_of_cluster*sizeof(float) );

  float* data_normalized = reinterpret_cast<float*>( malloc(data_dimension*data_set_size*sizeof(float)));
  


  srand(time(NULL));
  if(args.filename.empty())
    data_gen(addr_data,data_set_size, data_dimension);
  else
    read_input(filename, number_of_cluster, data_dimension, data_set_size, addr_data, non_padding_dimension);

  //normalize the data to 0-1
  normalization(data_dimension, data_set_size, addr_data, data_normalized);

  // normalize to 0-1 and scale it to 2**scale_factor-1
  normalization_scale(data_dimension, data_set_size, addr_data, addr_data_unsigned, dr_a_min, dr_a_max);

  //initialize centers
  initial_centroids(number_of_cluster, data_dimension, data_set_size, addr_center, addr_data_unsigned);
  convert_precision(precision, data_dimension, number_of_cluster, addr_center, low_prec_hw_center);

  //same center for sw and hw implementation
  memcpy(low_prec_sw_center, low_prec_hw_center, data_dimension*number_of_cluster*sizeof(uint32_t));

  ////////////////////////////////////////////////////////////////////
  //------------------bit serial manipulation-----------------------//
  ////////////////////////////////////////////////////////////////////
  vector<double> duration_vec;

  //store the data to bit-serial memory layout
  auto start_time = std::chrono::high_resolution_clock::now();
  mlweaving_on_sample(addr_data_weaving, addr_data_unsigned, data_set_size, data_dimension); 
  auto end_time = std::chrono::high_resolution_clock::now();
  double durationUs = std::chrono::duration_cast<std::chrono::microseconds>(end_time-start_time).count();
  std::cout << "ML weaving duration[us]**:" << durationUs << std::endl;


  if (args.runSw)
  {
    compute_low_precision_kmeans(precision, addr_data_unsigned, low_prec_sw_center, data_set_size, number_of_cluster, data_dimension, number_of_iteration, true);
  }

   /*
  if(args.runhw)
  {
    
    cProcess cproc(targetRegion, getpid());

    uint32_t *hMem_data;
    uint32_t *hMem_center;
    uint32_t *hMem_results;
    
    // Do the memory crap ...
    if(mapped) {
        uint32_t data_size = num_cl_tuple*16*sizeof(uint32_t);
        uint32_t n_pages_data = hugeAlloc ? ((data_size + hugePageSize - 1) / hugePageSize) : ((data_size + pageSize - 1) / pageSize);
        uint32_t center_size = data_dimension*number_of_cluster*sizeof(uint32_t);
        uint32_t n_pages_center = hugeAlloc ? ((center_size + hugePageSize - 1) / hugePageSize) : ((center_size + pageSize - 1) / pageSize);

        hMem_data = (uint32_t*) cproc.getMem({hugeAlloc ? CoyoteAlloc::HPF : CoyoteAlloc::REG, n_pages_data});
        hMem_center = (uint32_t*) cproc.getMem({hugeAlloc ? CoyoteAlloc::HPF : CoyoteAlloc::REG, n_pages_center});

        memcpy(hMem_center, low_prec_hw_center, data_dimension*number_of_cluster*sizeof(uint32_t));
        memcpy(hMem_data, addr_data_weaving, num_cl_tuple*16*sizeof(uint32_t));
    } else {
        hMem_data = addr_data_weaving;
    }
 
    // Set up config
    cproc.setCSR(number_of_cluster, 3);
    cproc.setCSR(data_dimension, 4);
    cproc.setCSR(precision, 5);
    cproc.setCSR(data_set_size, 6);
    cproc.setCSR((uint64_t)hMem_data, 7);
    cproc.setCSR(num_cl_tuple, 8);
    cproc.setCSR((uint64_t)hMem_center, 9);
    cproc.setCSR(num_cl_centroid, 10);
    cproc.setCSR((uint64_t)hMem_results, 11);
    cproc.setCSR(number_of_iteration* num_cl_centroid, 12);
    cproc.setCSR(number_of_iteration, 11);

    // Run this stuff
    int repetition = 1;
    vector<double> thruput_vec;
    //run the hardware multiple times

    for(int i = 0; i<repetition;i++) {
        start_time = std::chrono::high_resolution_clock::now();

        end_time = std::chrono::high_resolution_clock::now();

    }

    HWKmeans* hwkmeans = new HWKmeans(addr_data_weaving, low_prec_hw_center, data_set_size, data_dimension, number_of_cluster, num_cl_tuple, num_cl_centroid, number_of_iteration);
    
    int repetition = 1;
    vector<double> thruput_vec;
    //run the hardware multiple times
    for(int i = 0; i<repetition;i++)
    {
     start_time = std::chrono::high_resolution_clock::now();
     hwkmeans->run(number_of_iteration, precision, num_cl_centroid, num_cl_tuple);
     end_time = std::chrono::high_resolution_clock::now();
    
     durationUs = std::chrono::duration_cast<std::chrono::microseconds>(end_time-start_time).count();
     std::cout << "duration[us]**:" << durationUs << std::endl;
     double dataSizeGB = (double)((double)num_cl_tuple*(double)precision*(double)number_of_iteration*16.0*sizeof(uint32_t)/32.0)/1000.0/1000.0/1000.0;

     double thruput = dataSizeGB/(durationUs/1000.0/1000.0);
     std::cout<<"Datasize[GB]:"<<dataSizeGB<<" Throughput[GB/s]**:"<<thruput<<std::endl;
     duration_vec.push_back(durationUs);
     thruput_vec.push_back(thruput);

     //get the sse of the hardware results
     for (int j = 0; j < number_of_iteration; ++j)
     {
        uint32_t* center_result = hwkmeans->mResults+16*num_cl_centroid*j;
        convert_precision_de_normalization (data_dimension, number_of_cluster, precision, center_result, denomalized_center, dr_a_min, dr_a_max);
        float sse = get_sse(data_set_size, number_of_cluster, data_dimension, data_normalized, denomalized_center);
     }

        
    }

    //get status
    if (repetition>1)
    {
      totalDuration = accumulate(duration_vec.begin(), duration_vec.end(),0.0);
      avgDurationUs = totalDuration / (double)repetition; 
      double accu_thruput=accumulate(thruput_vec.begin(), thruput_vec.end(),0.0);
      double avgThruput = accu_thruput / (double)repetition;
      double durationStd = 0.0;
      double thruputStd = 0.0;
      for (int i = 0; i < repetition; ++i)
      {
         durationStd += (duration_vec[i]-avgDurationUs) *  (duration_vec[i]-avgDurationUs);
         thruputStd += (thruput_vec[i] - avgThruput) * (thruput_vec[i] - avgThruput);
      }
      durationStd /= repetition;
      thruputStd /= repetition;
   
      cout<<"&&avgThruput: "<<avgThruput<<";thruputStdr: "<<thruputStd<<endl;
      cout<<"&&avgDurationUs: "<<avgDurationUs<<";durationStd: "<<durationStd<<endl;
    }


   }
   */	


  free(addr_center);
  free(addr_data);
  free(addr_data_weaving);
  free(addr_data_unsigned);
  free(low_prec_sw_center);


};




