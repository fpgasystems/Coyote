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
#include "hw_kmeans.hpp"
#include <random>
#include <stdio.h>
#include <string.h>
#include <immintrin.h>
#include <tgmath.h>

#define KMEANS_OP 16

struct KMEANS_AFU_CONFIG{
   union {
      uint32_t          qword0[16];       // make it whole cacheline
      struct
      {
           void*          addr_center;
           void*          addr_data;
           void*          addr_result;
           uint64_t       data_set_size             : 64;
           uint32_t       num_cl_centroid           : 32;
           uint32_t       num_cl_tuple_low_prec     : 32; // indicate the number of cachelines need to fetch under low precision scheme
           uint32_t       number_of_cluster         : 32;
           uint32_t       data_dimension            : 32;
           uint16_t       number_of_iteration       : 16;
           uint8_t        precision                 : 8;
      };
   };
};



FthreadRec* fthread_low_prec_kmeans(
       FPGA* my_fpga,
       uint32_t*      addr_center,
       uint32_t*      addr_data,
       uint32_t*      addr_result,
       uint16_t       number_of_iteration,
       uint64_t       data_set_size,
       uint32_t       number_of_cluster,
       uint32_t       data_dimension,
       uint32_t       num_cl_tuple,
       uint32_t       num_cl_centroid,
       uint8_t        precision
       )
{

       //allocate config data structure
       KMEANS_AFU_CONFIG* afu_cfg = (struct KMEANS_AFU_CONFIG*)(my_fpga->malloc( sizeof(KMEANS_AFU_CONFIG) ));

       //fill in afu config data structure
       afu_cfg->addr_center = addr_center;
       afu_cfg->addr_data   = addr_data;
       afu_cfg->addr_result = addr_result;

       afu_cfg->number_of_iteration = number_of_iteration;
       afu_cfg->data_set_size = data_set_size;
       afu_cfg->num_cl_centroid = num_cl_centroid;
       afu_cfg->number_of_cluster = number_of_cluster;
       afu_cfg->data_dimension = data_dimension;
       afu_cfg->precision = precision;
       //indicate the number of cachelines need to fetch under low precision scheme
       afu_cfg->num_cl_tuple_low_prec = num_cl_tuple/32*precision;



       return new FthreadRec(my_fpga, KMEANS_OP, reinterpret_cast<unsigned char*>(afu_cfg), sizeof(KMEANS_OP) );
};


HWKmeans::HWKmeans(uint32_t* points, uint32_t* initial_center ,uint64_t size, uint32_t dimensions, uint32_t cluster, uint32_t num_cl_tuple, uint32_t num_cl_centroid, uint32_t number_of_iteration)
{
	my_fpga = new FPGA();

  //copy the data to mpoints
  mPoints =  reinterpret_cast<uint32_t*>(my_fpga->malloc(sizeof(uint32_t)*16*num_cl_tuple));
  memset(mPoints, 0, sizeof(uint32_t)*16*num_cl_tuple);
  memcpy(mPoints, points, sizeof(uint32_t)*16*num_cl_tuple);
  printf("Allocated data buffer/n");

  mSize = size;
  mClusters = cluster;
  mDimensions = dimensions;

  //copy the initial centroids into mcentroids
  mCentroids =  reinterpret_cast<uint32_t*>(my_fpga->malloc(sizeof(uint32_t)*16*num_cl_centroid));
  memset(mCentroids, 0, sizeof(uint32_t)*16*num_cl_centroid);
  memcpy(mCentroids, initial_center, sizeof(uint32_t)*mClusters*mDimensions);
  printf("Allocated center buffer\n");

  //allocate space for results
  mResults = reinterpret_cast<uint32_t*>( my_fpga->malloc(sizeof(uint32_t)*(number_of_iteration* num_cl_centroid*16)));
  printf("Allocated result buffer\n");
}

HWKmeans::~HWKmeans()
{
	my_fpga->free(mPoints);
	my_fpga->free(mCentroids);
	my_fpga->free(mResults);
}

void HWKmeans::print_debug_counters_expected_value(uint16_t number_of_iteration, uint8_t precision, uint32_t num_cl_tuple, uint32_t num_cl_centroid)
{
  uint32_t debug0 = num_cl_tuple/32*precision*number_of_iteration;
  uint32_t debug1 = num_cl_centroid ;
  uint32_t debug2 = ceil((float)mDimensions*(float)mSize/512.0) * number_of_iteration;
  uint32_t debug3 = number_of_iteration * mSize * mDimensions;
  uint32_t debug4 = mDimensions*mClusters*(number_of_iteration+1);
  uint32_t debug5 = (mDimensions*mClusters+mClusters+1)*number_of_iteration;
  uint32_t debug6 = mDimensions*mClusters*number_of_iteration;
  uint32_t debug7 = num_cl_centroid*number_of_iteration;
  printf("debug counter expected value:\n");
  printf("[0]fetch_engine num cl tuple: %u\n", debug0);
  printf("[1]fetch_engine num cl centroid:%u \n", debug1);
  printf("[2]transpose serial block:%u\n", debug2);
  printf("[3]transpose parallel output:%u\n", debug3);
  printf("[4]formatter output centroid:%u\n", debug4);
  printf("[5]aggregation count:%u\n", debug5);
  printf("[6]division data count:%u\n", debug6);
  printf("[7]wr engine cl cnt:%u\n", debug7);
}


void HWKmeans::run(uint16_t iter, uint8_t precision, uint32_t num_cl_centroid,uint32_t num_cl_tuple)
{
  // printf("addr_center:%lu\n", mCentroids);
  // printf("addr_data:%lu\n",mPoints);
  // printf("addr_result:%lu\n", mResults);

	Fthread KmeansOpR( fthread_low_prec_kmeans(my_fpga, mCentroids, mPoints, mResults, iter, mSize,mClusters,mDimensions,num_cl_tuple, num_cl_centroid, precision) );
  
   int sleeps = 0;
     while(true)
     {
        if(KmeansOpR.getFThreadRec()->get_status()->state == 4) break;
        SleepMilli(1);
        sleeps += 1;
        if(sleeps >= 40000)
        {
     printf("Killing AFU\n"); 
          my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioWrite64(8 * (32 + 6), AAL::btUnsigned64bitInt(0));
          SleepMilli(200);
        break;
        }
     }

     btUnsigned64bitInt v;
     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(8), &v);   // Freq

     printf("\nFreq: %lu", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(9), &v);   // Freq
     printf("RD Hits: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(10), &v);   // Freq
     printf("WR Hits: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(11), &v);   // Freq
     printf("vl0_rd: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(12), &v);   // Freq
     printf("vl0_wr: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(13), &v);   // Freq
     printf("vh0_wr: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(14), &v);   // Freq
     printf("vh1_wr: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(18), &v);   // Freq
     printf("vh0_rd: %lu, ", v); fflush(stdout);

    my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(19), &v);   // Freq
     printf("vh1_rd: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(15), &v);   // Freq
     printf("fiu state: %lu\n", v);  fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(16), &v);   // Freq
     printf("num reads: %lu\n", v);  fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(17), &v);   // Freq
     printf("num writes: %lu\n", v);  fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(20), &v);   // Freq
     printf("afu_tx_rd: %lu, ", v); fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(21), &v);   // Freq
     printf("afu_tx_wr: %lu\n", v);  fflush(stdout);
     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(22), &v);   // Freq
     printf("afu_rx_rd: %lu\n", v);  fflush(stdout);

     my_fpga->fpga_platform()->srvHndle->m_pALIMMIOService->mmioRead64(8 * uint32_t(23), &v);   // Freq
     printf("afu_rx_wr: %lu\n", v);  fflush(stdout);

     KmeansOpR.printStatusLine();
     print_debug_counters_expected_value(iter, precision, num_cl_tuple, num_cl_centroid);
    KmeansOpR.join();
    
}

uint64_t HWKmeans::getSSE(uint32_t num_cl_centroid, uint32_t precision)
{
   
   // for(int i =0; i<precision;i++)
   // {
	  //  printf("SSE:%llu\n", mResults[precision*num_cl_centroid*16+16*i]);
   // }
   
   // return 0;
}


//print the centroid of every iteration
void HWKmeans::printCentroids(uint32_t number_of_iteration, uint32_t num_cl_centroid)
{
   std::cout << "Centroids:" << std::endl;
   for (int i = 0; i < number_of_iteration; ++i)
   {
      printf("iteration:%d\n", i);
      for (uint32_t c = 0; c < mClusters; ++c) {
        std::cout << "centroid[" << c << "]: ";
        for (uint32_t d = 0; d < mDimensions; ++d) {
           std::cout << " " << mResults[16*num_cl_centroid*i+c*mDimensions+d];
          }
      std::cout << std::endl;
      }
   }
   
}




