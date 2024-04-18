// /*
//  * Copyright (c) 2019, Systems Group, ETH Zurich
//  * All rights reserved.
//  *
//  * Redistribution and use in source and binary forms, with or without modification,
//  * are permitted provided that the following conditions are met:
//  *
//  * 1. Redistributions of source code must retain the above copyright notice,
//  * this list of conditions and the following disclaimer.
//  * 2. Redistributions in binary form must reproduce the above copyright notice,
//  * this list of conditions and the following disclaimer in the documentation
//  * and/or other materials provided with the distribution.
//  * 3. Neither the name of the copyright holder nor the names of its contributors
//  * may be used to endorse or promote products derived from this software
//  * without specific prior written permission.
//  *
//  * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
//  * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  * IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//  * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//  * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  */
// #include <stdio.h> 
// #include <unistd.h> 
// #include <stdlib.h>
// #include <malloc.h> 
// #include <assert.h> 
// #include <math.h>   
// #include <iostream> 
// #include <fstream>      
// #include <sstream>     
// #include <string.h> 
// #include <string> 
// #include <limits>

// #include "utils.hpp"
// #include "classical_kmeans.hpp"

// using namespace std;
// #define SCALE_FACTOR 32
 

// void compute_low_precision_kmeans(int precision, uint32_t* objects, uint32_t* clusters_ref, int numObjs, int numClusters, int numCoords, int max_iter, bool user_specify_precision){

//     int* member_ref = NULL;
//     int status = posix_memalign((void**)&member_ref, 64, sizeof(int)*numObjs);
//     /* initialize membership[] */
//     for (int i=0; i<numObjs; i++){
//   		member_ref[i] = 0;
//   	}

// 	int total_loop = 0;
	
// 	//initialize temp arrays
// 	unsigned int mem_size_cluster = sizeof(uint64_t)* numClusters * numCoords;
//   uint64_t* newClusters = NULL;
// 	status = posix_memalign((void**)&newClusters, 64, mem_size_cluster);
	
// 	unsigned int mem_size_cluster_size = sizeof(uint32_t)* numClusters;
//     uint32_t * newClusterSize = NULL;
// 	status = posix_memalign((void**)&newClusterSize, 64, mem_size_cluster_size);
    
// 	/* need to initialize newClusterSize and newClusters[0] to all 0 */
//     for (int i=0; i<numClusters; i++){
//   		newClusterSize[i] = 0;
//   		for (int j=0; j<numCoords; j++){
//     			newClusters[i*numCoords+j] = 0;
//     		}
//   	}

//     //if user specify precision, run single precision algorithm 
//     if (user_specify_precision)
//     {
//         low_precision_kmeans(numObjs,numClusters, numCoords, member_ref, newClusterSize, newClusters, objects, clusters_ref, max_iter, precision, &total_loop);
//     }
// 	//Clean temp arrays
// 	free (newClusterSize);
// 	free (newClusters);
// }


// void low_precision_kmeans(int numObjs, int numClusters, int numCoords, int* member_ref, uint32_t* newClusterSize, uint64_t* newClusters, uint32_t* objects, uint32_t* clusters_ref, int max_loop, int precision, int* total_loop)
// {
//     //allocate space for low precision features
//     uint32_t* low_precision_feature = NULL;
//     int status =posix_memalign((void**)&low_precision_feature, 64, sizeof(uint32_t)*numObjs*numCoords);

//     //convert precision
//     convert_precision( precision,  numCoords, numObjs, objects, low_precision_feature);

//     uint64_t* centroid_norm_half = NULL;
//     status =posix_memalign((void**)&centroid_norm_half, 64, sizeof(uint64_t)*numClusters*numCoords);

//     do {

//         for (int i = 0; i < numClusters; ++i)
//         {
//           centroid_norm_half[i] = 0;
//           for (int j = 0; j < numCoords; ++j)
//           {
//             centroid_norm_half[i] += (uint64_t)clusters_ref[i*numCoords+j] * (uint64_t)clusters_ref[i*numCoords+j];
//           }
//           centroid_norm_half[i] = 0.5*centroid_norm_half[i];
//         }

//         uint64_t loss = 0;

//         for (int i=0; i<numObjs; i++) {
        
//             int64_t min_dist = numeric_limits<int64_t>::max();
//             int index = 0;
        
//             for (int j=0; j<numClusters; j++) {
//                 int64_t dist = 0;
//                 for (int k=0; k<numCoords; k++){
//                     int64_t coor_1, coor_2;
//                     coor_1 = (int64_t)low_precision_feature [i*numCoords+k];
//                     coor_2 = (int64_t)clusters_ref [j*numCoords+k];
//                     dist += (coor_1 * coor_2);
//                 }
//                 dist = (int64_t)centroid_norm_half[j] - dist;
//                 if (dist <= min_dist) { /* find the min and its array index */
//                     min_dist = dist;
//                     index    = j;
//                 }
//             }

//             // assign the membership to object i
//             member_ref[i] = index;
//             loss = loss + min_dist;

//             // update new cluster centers : sum of objects located within 
//             newClusterSize[index]++;
//             for (int j=0; j<numCoords; j++){
//                            newClusters[index*numCoords+j] += low_precision_feature[i*numCoords+j];
//             }
//         }


//         // average the sum and replace old cluster centers with newClusters 
//         for (int i=0; i<numClusters; i++) {
//             for (int j=0; j<numCoords; j++) {
//                 if (newClusterSize[i] > 0){
//                     clusters_ref[i*numCoords+j] = (uint32_t)(newClusters[i*numCoords+j] / newClusterSize[i]) ;
//                 }
//                 else {
//                     clusters_ref[i*numCoords+j] = 0;
//                 }

//                 newClusters[i*numCoords+j] = 0;  
//             }
//             newClusterSize[i] = 0;  
//         }

//         (*total_loop)++;


//     } while ((*total_loop) < max_loop);   
// }


// void printCentroids(uint32_t*centroid, uint32_t numClusters, uint32_t numCoords, uint32_t number_of_iteration)
// {
//    std::cout << "Centroids:" << std::endl;
//    for (int i = 0; i < number_of_iteration; ++i)
//    {
//       for (uint32_t c = 0; c < numClusters; ++c) {
//         std::cout << "centroid[" << c << "]: ";
//         for (uint32_t d = 0; d < numCoords; ++d) {
//            std::cout << " " << centroid[c*numCoords+d];
//           }
//       std::cout << std::endl;
//       }
//    }
   
// }


// void normalization_scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features ,float* dr_a_min, float* dr_a_max)
// {
//    double scale = SCALE_FACTOR;
//    printf("\nStart normalization 0 - 1 and scale to (2^%lf-1):\n", scale);

//     for (int j = 0; j < nfeatures; ++j)
//     {
//         float amin = numeric_limits<float>::max();
//         float amax = numeric_limits<float>::min();

//         for (int i = 0; i < npoints; ++i)
//         {
//             float a_here = features[i*nfeatures+j];
//             if (a_here > amax)
//                 amax = a_here;
//             if (a_here < amin)
//                 amin = a_here;
//         }
//         dr_a_min[j]  = amin; //set to the global variable for pm
//         dr_a_max[j]  = amax;
//         float arange = amax - amin;
//         if (arange > 0)
//         {
//             for (int i = 0; i < npoints; ++i)
//             {
//                 float tmp = ((features[i*nfeatures+j]-amin)/arange);
//                 scaled_unsigned_features[i*nfeatures+j] = (uint32_t) (tmp * ((pow(2.0,scale))-1)); 
// 	     }
//         }
//     }


//    printf("normalization and scale finished\n");

// }


// void normalization(int nfeatures, int npoints, float* features, float* normalized_features)
// {

//   printf("\nStart normalization 0 - 1:\n");

//     for (int j = 0; j < nfeatures; ++j)
//     {
//         float amin = numeric_limits<float>::max();
//         float amax = numeric_limits<float>::min();

//         for (int i = 0; i < npoints; ++i)
//         {
//             float a_here = features[i*nfeatures+j];
//             if (a_here > amax)
//                 amax = a_here;
//             if (a_here < amin)
//                 amin = a_here;
//         }
//         float arange = amax - amin;
//         if (arange > 0)
//         {
//             for (int i = 0; i < npoints; ++i)
//             {
//                 float tmp = ((features[i*nfeatures+j]-amin)/arange);
//                 normalized_features[i*nfeatures+j] = tmp;
//             }
//         }
//     }


//   printf("normalization finished\n");
// }

// void convert_precision(int precision, int nfeatures, int npoints, uint32_t* features, uint32_t* low_precision_feature)
// {
//     uint32_t tmp;
//     for (int i = 0; i < npoints; ++i)
//     {
//       for (int j = 0; j < nfeatures; ++j)
//       {
//          tmp = ((uint32_t)features[i*nfeatures+j]) >> (SCALE_FACTOR-precision);
//          low_precision_feature[i*nfeatures+j] = (uint32_t)tmp;
//       }
//     }
// }

// void initial_centroids(int numClusters, int numCoords, int numObjs, uint32_t* cluster, uint32_t* objects)
// {
//     srand(1);
//     /* randomly pick cluster centers */
//     printf("randomly select cluster centers\n");
//     for (int i=0; i<numClusters; i++) {
//         int n = (int)rand() % numObjs;     
//         for (int j=0; j<numCoords; j++)
//         {
//             cluster[i*numCoords+j] = objects[n*numCoords+j];
//         }
//     }
// }


// float get_sse(int numObjs, int numClusters, int numCoords, float * objects, float * clusters_ref)
// {
//     float loss = 0.0f;
//     for (int i=0; i<numObjs; i++) {
        
//         float min_dist = 3.402816466e+38F;
//         int index = 0;

//         for (int j=0; j<numClusters; j++) {
//             float dist = 0.0f;
//             for (int k=0; k<numCoords; k++){
//                 float coor_1, coor_2;
//                 coor_1 = objects [i*numCoords+k];
//                 coor_2 = clusters_ref [j*numCoords+k];
//                 dist += (coor_1 - coor_2)*(coor_1 - coor_2);
                
//             }
//             if (dist < min_dist) { /* find the min and its array index */
//                 min_dist = dist;
//                 index    = j;
//             }
//         }
//         loss = loss + min_dist;
//     }

//     return loss;

// }

// void convert_precision_de_normalization (int nfeatures, int npoints, int precision, uint32_t* low_precision_feature, float* denomalized_features, float* dr_a_min, float* dr_a_max)
// {
//     //printf("start de-normalization\n");
//     for (int j = 0; j< nfeatures; ++j)
//     {
//         // float arange = dr_a_max[j] - dr_a_min[j];
//         for (int i = 0; i < npoints; ++i)
//         {
//             float tmp = (float)low_precision_feature[i*nfeatures+j]/ ((pow(2.0,precision))-1);
//             denomalized_features [i*nfeatures+j] = tmp;
//         }
//     }
// }
