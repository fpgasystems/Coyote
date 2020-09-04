#ifndef __FKMEANS_HPP__
#define __FKMEANS_HPP__

#include <iostream>
#include <locale>
#include <thread>
#include <cstdlib>
#include <ctime>
#include <cmath>
#include <stdio.h>

#include "fDev.hpp"
#include "fJob.hpp"
#include "fDefs.hpp"

#include "mlweaving.h"
#include "classical_kmeans.h"
#include "utils.hpp"

#define KMEANS_OP 16
#define TUPLES_PER_CACHE_LINE 16

using namespace std;

//static const struct timespec SLEEP_NS {.tv_sec = 0, .tv_nsec = 1000};

/**
 * Hyperloglog
 */
class fKmeans : public fJob {
private:
    uint16_t number_of_iterations;
    uint64_t data_set_size;
    uint32_t number_of_clusters;
    uint32_t data_dimension;

public:
    fKmeans(uint16_t number_of_iterations, uint64_t data_set_size, uint32_t number_of_clusters, uint32_t data_dimension,         
        uint32_t id, uint32_t priority) : fJob(id, priority, OPER_KMEANS) { 
            this->number_of_iterations = number_of_iterations;
            this->data_set_size = data_set_size;
            this->number_of_clusters = number_of_clusters;
            this->data_dimension = data_dimension;
        }

    void run() {
        uint32_t number_of_tuples_center = number_of_clusters * data_dimension;
        uint32_t number_of_tuples_dataset = data_set_size  * data_dimension;

        uint32_t num_cl_centroid = ceil((float)number_of_tuples_center/ (float)TUPLES_PER_CACHE_LINE);
        uint32_t num_cl_tuple = compute_num_cl_tuples(data_set_size, data_dimension);

        // Allocation of memory space
        float* addr_data = reinterpret_cast<float*>( malloc(data_dimension*data_set_size*sizeof(float)));
        memset(addr_data, 0 , data_dimension*data_set_size*sizeof(float));
        //uint32_t* addr_data_unsigned = reinterpret_cast<uint32_t*>( malloc(data_dimension*data_set_size*sizeof(uint32_t)));
        uint64_t n_pages = 20;
        uint32_t* addr_data_unsigned = (uint32_t*)fdev->getHostMem(n_pages);
        uint32_t* result_center = (uint32_t*)fdev->getHostMem(n_pages);


        uint32_t* addr_center = NULL;
        int status =posix_memalign((void**)&addr_center, 64, num_cl_centroid*16*sizeof(uint32_t) );
        memset(addr_center, 0 , num_cl_centroid*16*sizeof(uint32_t));

        uint32_t* sw_center = NULL;
        status=posix_memalign((void**)&sw_center, 64, data_dimension*number_of_clusters*sizeof(uint32_t) );
        memset(sw_center, 0 , data_dimension*number_of_clusters*sizeof(uint32_t));

        uint32_t* hw_center = NULL;
        status=posix_memalign((void**)&hw_center, 64, data_dimension*number_of_clusters*sizeof(uint32_t) );
        memset(hw_center, 0 , data_dimension*number_of_clusters*sizeof(uint32_t));

        //uint32_t* result_center = NULL;
        //status=posix_memalign((void**)&result_center, 64, sizeof(uint32_t)*(number_of_iterations* num_cl_centroid*16) );

        float* dr_a_min    = (float *)malloc(data_dimension*sizeof(float)); //to store the minimum value of features.....
        float* dr_a_max    = (float *)malloc(data_dimension*sizeof(float)); //to store the miaximum value of features.....

        float* nomalized_center = NULL;
        status=posix_memalign((void**)&nomalized_center, 64, data_dimension*number_of_clusters*sizeof(float) );

        float* data_normalized = reinterpret_cast<float*>( malloc(data_dimension*data_set_size*sizeof(float)));

        // Generate data
        srand(time(NULL));
        data_gen(addr_data,data_set_size, data_dimension);

        normalization(data_dimension, data_set_size, addr_data, data_normalized);
        normalization_scale(data_dimension, data_set_size, addr_data, addr_data_unsigned, dr_a_min, dr_a_max);


        initial_centroids(number_of_clusters, data_dimension, data_set_size, addr_center, addr_data_unsigned);
        printCentroids(addr_center, number_of_clusters, data_dimension, 1);

        memcpy(hw_center, addr_center, data_dimension*number_of_clusters*sizeof(uint32_t));
        memcpy(sw_center, addr_center, data_dimension*number_of_clusters*sizeof(uint32_t));

        // Run SW
        std::cout << "** SW ***********************************************" << std::endl;
        compute_kmeans(addr_data_unsigned, sw_center, data_set_size, number_of_clusters, data_dimension, number_of_iterations, true);
        descale_normalization (data_dimension, number_of_clusters, sw_center, nomalized_center, dr_a_min, dr_a_max);
        for (int n = 0; n < number_of_clusters; ++n)
            {
            for (int m = 0; m < data_dimension; ++m)
            {
                printf("%f ", nomalized_center[n*data_dimension+m]);
            }
            printf("\n");
            }
        float sse = get_sse(data_set_size, number_of_clusters, data_dimension, data_normalized, nomalized_center);
        printf("final sse:%f\n", sse);

        // Run HW
        std::cout << "** HW ***********************************************" << std::endl;
        // Load params
        fdev->setCSR(data_set_size, 2);
        std::cout << "Data set size: " << fdev->getCSR(2) << std::endl;
        fdev->setCSR(number_of_clusters, 3);
        std::cout << "Number of clusters: " << fdev->getCSR(3) << std::endl;
        fdev->setCSR(data_dimension, 4);
        std::cout << "Data dimension: " << fdev->getCSR(4) << std::endl;
        fdev->setCSR(0x1, 0);

        for(int i = 0; i < number_of_iterations; i++) {
            auto start_time = std::chrono::high_resolution_clock::now();
            //std::cout << "CENTROIDS: " << sizeof(uint32_t)*16*num_cl_centroid << std::endl;
            fdev->setCSR(0x0, 5);
            //std::cout << fdev->getCSR(5) << std::endl;
            fdev->readFrom((uint64_t*)hw_center, sizeof(uint32_t)*16*num_cl_centroid);
            //std::cout << "Centroids read" << std::endl;
            //std::cout << "DATA SRC: " << sizeof(uint32_t)*16*num_cl_tuple << std::endl;
            //std::cout << "DATA DST: " << sizeof(uint32_t)*(number_of_iterations* num_cl_centroid*16) << std::endl;
            fdev->setCSR(0x1, 5);
            //std::cout << fdev->getCSR(5) << std::endl;
            fdev->transferData((uint64_t*)addr_data_unsigned, (uint64_t*)result_center,
             sizeof(uint32_t)*16*num_cl_tuple, sizeof(uint32_t)*(number_of_iterations* num_cl_centroid*16), true);
            auto end_time = std::chrono::high_resolution_clock::now();
            //std::cout << "Completed iteration " << i << std::endl;

            double durationUs = std::chrono::duration_cast<std::chrono::microseconds>(end_time-start_time).count();
            std::cout << "duration[us]**:" << durationUs << std::endl;
            double dataSizeGB = (double)((double)num_cl_tuple*(double)number_of_iterations*16.0*sizeof(uint32_t))/1000.0/1000.0/1000.0;
            double thruput = dataSizeGB/(durationUs/1000.0/1000.0);
            std::cout<<"Datasize[GB]:"<<dataSizeGB<<" Throughput[GB/s]**:"<<thruput<<std::endl;
        }

       

        std::cout << "Centroids:" << std::endl;
        for (int i = 0; i < number_of_iterations; ++i)
        {
            printf("iteration:%d\n", i);
            for (uint32_t c = 0; c < number_of_clusters; ++c) {
                std::cout << "centroid[" << c << "]: ";
                for (uint32_t d = 0; d < data_dimension; ++d) {
                std::cout << " " << result_center[16*num_cl_centroid*i+c*data_dimension+d];
                }
            std::cout << std::endl;
            }
        }
        /*
        for (int j = 0; j < number_of_iterations; ++j)
        {
            uint32_t* center_result = hwkmeans->mResults+16*num_cl_centroid*j;
            descale_normalization (data_dimension, number_of_cluster, center_result, nomalized_center, dr_a_min, dr_a_max);
            printf("normalized center:\n");
            for (int n = 0; n < number_of_cluster; ++n)
            {
            for (int m = 0; m < data_dimension; ++m)
            {
                printf("%f ", nomalized_center[n*data_dimension+m]);
            }
            printf("\n");
            }
            float loss = get_sse(data_set_size, number_of_cluster, data_dimension, data_normalized, nomalized_center);
            printf("iteration %d: sse:%f\n", j, loss);
        }
        */

       fdev->freeHostMem((uint64_t*)addr_data_unsigned, n_pages);
       fdev->freeHostMem((uint64_t*)result_center, n_pages);

        // Free memory
        free(addr_center);
        free(addr_data);
        //free(addr_data_unsigned);
        free(sw_center);
        free(hw_center);
        //free(result_center);


    }
};


#endif 