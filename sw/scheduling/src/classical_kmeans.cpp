#include <stdio.h> 
#include <unistd.h> 
#include <stdlib.h>
#include <malloc.h> 
#include <assert.h> 
#include <math.h>   
#include <iostream> 
#include <fstream>      
#include <sstream>     
#include <string.h> 
#include <string> 
#include <limits>

#include "utils.hpp"
#include "classical_kmeans.h"

using namespace std;
#define SCALE_FACTOR 16
 

void compute_kmeans( uint32_t* objects, uint32_t* clusters_ref, int numObjs, int numClusters, int numCoords, int max_iter, bool user_specify_precision){

    int* member_ref = NULL;
    int status = posix_memalign((void**)&member_ref, 64, sizeof(int)*numObjs);
    /* initialize membership[] */
    for (int i=0; i<numObjs; i++){
  		member_ref[i] = 0;
  	}

	int total_loop = 0;
	
	//initialize temp arrays
	unsigned int mem_size_cluster = sizeof(uint64_t)* numClusters * numCoords;
    uint64_t* newClusters = NULL;
	status = posix_memalign((void**)&newClusters, 64, mem_size_cluster);
	
	unsigned int mem_size_cluster_size = sizeof(uint32_t)* numClusters;
    uint32_t * newClusterSize = NULL;
	status = posix_memalign((void**)&newClusterSize, 64, mem_size_cluster_size);
    
	/* need to initialize newClusterSize and newClusters[0] to all 0 */
    for (int i=0; i<numClusters; i++){
  		newClusterSize[i] = 0;
  		for (int j=0; j<numCoords; j++){
    			newClusters[i*numCoords+j] = 0;
    		}
  	}

    
	
    run_kmeans(numObjs,numClusters, numCoords, member_ref, newClusterSize, newClusters, objects, clusters_ref, max_iter, &total_loop);
    

	free (newClusterSize);
	free (newClusters);
}


void run_kmeans(int numObjs, int numClusters, int numCoords, int* member_ref, uint32_t* newClusterSize, uint64_t* newClusters, uint32_t* objects, uint32_t* clusters_ref, int max_loop, int* total_loop)
{

    // printf("data:\n");
    // for (int i = 0; i < numObjs; ++i)
    // {
    //   printf("%d:", i);
    //   for (int j = 0; j < numCoords; ++j)
    //   {
    //     printf("%d ", objects[i*numCoords + j]);
    //   }
    //   printf("\n");
    // }

    do {

        uint64_t loss = 0;

        for (int i=0; i<numObjs; i++) {
        
            int64_t min_dist = numeric_limits<int64_t>::max();
            int index = 0;
        
            // printf("%d:", i);
            for (int j=0; j<numClusters; j++) {
                int64_t dist = 0;
                for (int k=0; k<numCoords; k++){
                    int64_t coor_1, coor_2;
                    coor_1 = (int64_t)objects [i*numCoords+k];
                    coor_2 = (int64_t)clusters_ref [j*numCoords+k];
                    dist += (uint64_t)((coor_1 - coor_2)*(coor_1 - coor_2));
                    // dist += (coor_1 * coor_2);
                }
                // dist = (int64_t)centroid_norm_half[j] - dist;
                // printf("%ld ", dist);
                if (dist <= min_dist) { /* find the min and its array index */
                    min_dist = dist;
                    index    = j;
                }
            }

            // assign the membership to object i
            member_ref[i] = index;
            // if (i%4==2)
            // {
               // printf(" min_dist:%ld,cluster:%u\n",min_dist,index);
            // }
            
            loss = loss + min_dist;

            // update new cluster centers : sum of objects located within 
            newClusterSize[index]++;
            for (int j=0; j<numCoords; j++){
                           newClusters[index*numCoords+j] += objects[i*numCoords+j];
            }
        }

        printf("sum\n");
        for (int i = 0; i < numClusters; ++i)
        {
          for (int j = 0; j < numCoords; ++j)
          {
            printf("%lu ", newClusters[i*numCoords+j]);
          }
          printf("\n");
        }

        // average the sum and replace old cluster centers with newClusters 
        printf("count\n");
        for (int i=0; i<numClusters; i++) {
            for (int j=0; j<numCoords; j++) {
                if (newClusterSize[i] > 0){
                    clusters_ref[i*numCoords+j] = (uint32_t)(newClusters[i*numCoords+j] / newClusterSize[i]) ;
                }
                else {
                    clusters_ref[i*numCoords+j] = 0;
                }

                newClusters[i*numCoords+j] = 0;  
            }
            printf("%u ",newClusterSize[i]);
            newClusterSize[i] = 0;  
        }
        printf("\n");
        printCentroids(clusters_ref, numClusters, numCoords,1);
        printf ("# iteration:%u, loss_low_prec is:@ %lu\n", *total_loop, loss);
        

        (*total_loop)++;


    } while ((*total_loop) < max_loop);   
}


void printCentroids(uint32_t*centroid, uint32_t numClusters, uint32_t numCoords, uint32_t number_of_iteration)
{
   std::cout << "Centroids:" << std::endl;
   for (int i = 0; i < number_of_iteration; ++i)
   {
      // printf("iteration:%u\n", i);
      for (uint32_t c = 0; c < numClusters; ++c) {
        std::cout << "centroid[" << c << "]: ";
        for (uint32_t d = 0; d < numCoords; ++d) {
           std::cout << " " << centroid[c*numCoords+d];
          }
      std::cout << std::endl;
      }
   }
   
}


void normalization_scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features ,float* dr_a_min, float* dr_a_max)
{
   double scale = SCALE_FACTOR;
   printf("\nStart normalization 0 - 1 and scale to (2^%lf-1):\n", scale);

    for (int j = 0; j < nfeatures; ++j)
    {
        float amin = numeric_limits<float>::max();
        float amax = numeric_limits<float>::min();

        for (int i = 0; i < npoints; ++i)
        {
            float a_here = features[i*nfeatures+j];
            if (a_here > amax)
                amax = a_here;
            if (a_here < amin)
                amin = a_here;
        }
        dr_a_min[j]  = amin; //set to the global variable for pm
        dr_a_max[j]  = amax;
        printf("column: %d, min:%f, max:%f\n", j, amin, amax);
        float arange = amax - amin;
        if (arange > 0)
        {
            for (int i = 0; i < npoints; ++i)
            {
                float tmp = ((features[i*nfeatures+j]-amin)/arange);
                scaled_unsigned_features[i*nfeatures+j] = (uint32_t) (tmp * ((pow(2.0,scale))-1)); 
            }
        }
    }


   printf("normalization and scale finished\n");

  //  for (int i = 0; i < npoints; ++i)
  //  {
  //    for (int j = 0; j < nfeatures; ++j)
  //    {
  //      printf("%u ", scaled_unsigned_features[i*nfeatures+j]);
  //    }
  //    printf("\n");
  //  }
}

void scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features,float* dr_a_min, float* dr_a_max)
{
   double scale = SCALE_FACTOR;
   printf("\nStart scale to %lf:\n", scale);

    for (int j = 0; j < nfeatures; ++j)
    {
        float amin = numeric_limits<float>::max();
        float amax = numeric_limits<float>::min();

        for (int i = 0; i < npoints; ++i)
        {
            float a_here = features[i*nfeatures+j];
            if (a_here > amax)
                amax = a_here;
            if (a_here < amin)
                amin = a_here;
        }
        dr_a_min[j]  = amin; //set to the global variable for pm
        dr_a_max[j]  = amax;
        printf("column: %d, min:%f, max:%f\n", j, amin, amax);
        for (int i = 0; i < npoints; ++i)
        {
            scaled_unsigned_features[i*nfeatures+j] = (uint32_t) ((features[i*nfeatures+j] - amin) * scale); 
        }
        
    }


   printf("scale finished\n");

    for (int i = 0; i < npoints; ++i)
    {
      for (int j = 0; j < nfeatures; ++j)
      {
        printf("%u ", scaled_unsigned_features[i*nfeatures+j]);
      }
      printf("\n");
    }
}


void normalization(int nfeatures, int npoints, float* features, float* normalized_features)
{

  printf("\nStart normalization 0 - 1:\n");

    for (int j = 0; j < nfeatures; ++j)
    {
        float amin = numeric_limits<float>::max();
        float amax = numeric_limits<float>::min();

        for (int i = 0; i < npoints; ++i)
        {
            float a_here = features[i*nfeatures+j];
            if (a_here > amax)
                amax = a_here;
            if (a_here < amin)
                amin = a_here;
        }
        //printf("column: %d, min:%f, max:%f\n", j, amin, amax);
        float arange = amax - amin;
        if (arange > 0)
        {
            for (int i = 0; i < npoints; ++i)
            {
                float tmp = ((features[i*nfeatures+j]-amin)/arange);
                normalized_features[i*nfeatures+j] = tmp;
            }
        }
    }

  // for (int i = 0; i < npoints; ++i)
  //  {
  //   for (int j = 0; j < nfeatures; ++j)
  //   {
  //     printf("%f ", normalized_features[i*nfeatures+j]);
  //   }
  //   printf("\n");
  //  }

  printf("normalization finished\n");
}

void convert_precision(int precision, int nfeatures, int npoints, uint32_t* features, uint32_t* low_precision_feature)
{
    //printf("precision:%d\n", precision);
    uint32_t tmp;
    for (int i = 0; i < npoints; ++i)
    {
      for (int j = 0; j < nfeatures; ++j)
      {
         tmp = ((uint32_t)features[i*nfeatures+j]) >> (SCALE_FACTOR-precision);
         // tmp = (uint32_t)features[i*nfeatures+j];
         low_precision_feature[i*nfeatures+j] = (uint32_t)tmp;
      }
    }
}

void initial_centroids(int numClusters, int numCoords, int numObjs, uint32_t* cluster, uint32_t* objects)
{
    srand(1);
    /* randomly pick cluster centers */
    printf("randomly select cluster centers\n");
    for (int i=0; i<numClusters; i++) {
        int n = (int)rand() % numObjs;     
        //int n = (numObjs/numClusters) * i;
        printf("%d: ", n);
        for (int j=0; j<numCoords; j++)
        {
            cluster[i*numCoords+j] = objects[n*numCoords+j];
            printf("%u ", cluster[i*numCoords+j]);
        }
        printf("\n");
    }
}


float get_sse(int numObjs, int numClusters, int numCoords, float * objects, float * clusters_ref)
{
    float loss = 0.0f;
    for (int i=0; i<numObjs; i++) {
        
        float min_dist = 3.402816466e+38F;
        int index = 0;

        for (int j=0; j<numClusters; j++) {
            float dist = 0.0f;
            for (int k=0; k<numCoords; k++){
                float coor_1, coor_2;
                coor_1 = objects [i*numCoords+k];
                coor_2 = clusters_ref [j*numCoords+k];
                dist += (coor_1 - coor_2)*(coor_1 - coor_2);
                
            }
            if (dist < min_dist) { /* find the min and its array index */
                min_dist = dist;
                index    = j;
            }
        }
        loss = loss + min_dist;
    }

    return loss;

}

void descale_normalization (int nfeatures, int npoints, uint32_t* feature, float* denomalized_features, float* dr_a_min, float* dr_a_max)
{
    printf("start de-scale and normalization\n");
    float scale = SCALE_FACTOR;
    for (int j = 0; j< nfeatures; ++j)
    {
        float arange = dr_a_max[j] - dr_a_min[j];
        for (int i = 0; i < npoints; ++i)
        {
            // float tmp = (float)(feature[i*nfeatures+j] + dr_a_min[j])/ (float)scale;
            // tmp = (tmp - dr_a_min[j]) / (arange);
            // denomalized_features [i*nfeatures+j] = tmp;
            float tmp = (float)feature[i*nfeatures+j]/ (float)((pow(2.0,scale))-1);
            denomalized_features [i*nfeatures+j] = tmp;
        }
    }
}
// void compute_reference_kmeans(float* objects, float* clusters_ref, int* member_ref, int numObjs, int numClusters, int numCoords, int iter, float threshold){

	
//     /* initialize membership[] */
//     for (int i=0; i<numObjs; i++){
// 		member_ref[i] = 0;
// 	}

// 	int loop = 0;
// 	float delta;
// 	float loss;
//     // float threshold = 0.002;

// 	//initialize temp arrays
// 	unsigned int mem_size_cluster = sizeof(float)* numClusters * numCoords;
//     float* newClusters = NULL;
// 	posix_memalign((void**)&newClusters, AOCL_ALIGNMENT, mem_size_cluster);
	
// 	unsigned int mem_size_cluster_size = sizeof(int)* numClusters;
//     unsigned int * newClusterSize = NULL;
// 	posix_memalign((void**)&newClusterSize, AOCL_ALIGNMENT, mem_size_cluster_size);
    
// 	/* need to initialize newClusterSize and newClusters[0] to all 0 */
//     for (int i=0; i<numClusters; i++){
// 		newClusterSize[i] = 0;
// 		for (int j=0; j<numCoords; j++){
// 			newClusters[i*numCoords+j] = 0.0f;
// 		}
// 	}
// 	float sse_change = 10000000;
//     float previous_sse = 0.0f;

//     float* old_center = NULL;
//     posix_memalign((void**)&old_center, 64, sizeof(float)*numClusters*numCoords);
//     float center_change_norm = 1000000;

//     float variance = get_change_center_thres (objects, numCoords, numObjs);
//     float change_center_thres = variance*threshold;    

//     do {
//         delta = 0.0;
//         loss = 0.0;
//         memcpy(old_center, clusters_ref, sizeof(float)*numClusters*numCoords);
//         for (int i=0; i<numObjs; i++) {
		
// 			float min_dist = INFINITY;
// 			int index = 0;
		
			
// 			for (int j=0; j<numClusters; j++) {
// 				float dist = 0.0f;
// 				for (int k=0; k<numCoords; k++){
// 					float coor_1, coor_2;
// 					coor_1 = objects [i*numCoords+k];
// 					coor_2 = clusters_ref [j*numCoords+k];
// 					dist += (coor_1 - coor_2)*(coor_1 - coor_2);
					
// 				}
// 				if (dist < min_dist) {  find the min and its array index 
// 					min_dist = dist;
// 					index    = j;
// 				}
// 			}
//             loss = loss + min_dist;

//             // if membership changes, increase delta by 1
//             if (member_ref[i] != index) {delta += 1.0;}

//             // assign the membership to object i
//             member_ref[i] = short(index);

//             // update new cluster centers : sum of objects located within 
//             newClusterSize[index]++;
//             for (int j=0; j<numCoords; j++){
//                			   newClusters[index*numCoords+j] += objects[i*numCoords+j];
// 			}
//         }

//         // average the sum and replace old cluster centers with newClusters 
//         center_change_norm = 0;
//         for (int i=0; i<numClusters; i++) {
//             for (int j=0; j<numCoords; j++) {
//                 if (newClusterSize[i] > 0){
//                     clusters_ref[i*numCoords+j] = newClusters[i*numCoords+j] / newClusterSize[i];
// 				}
//                 newClusters[i*numCoords+j] = 0.0f;  
//                 center_change_norm = center_change_norm + (clusters_ref[i*numCoords+j]-old_center[i*numCoords+j])*(clusters_ref[i*numCoords+j]-old_center[i*numCoords+j]);

//             }
//             newClusterSize[i] = 0;  
//         }
            
            
//         delta /= numObjs;
//         sse_change = abs(loss - previous_sse);
//         previous_sse = loss;

//         loss = loss / ((1<<SCALE_FACTOR)-1);
//         loss = loss / ((1<<SCALE_FACTOR)-1);
        
// 		printf ("#iter: %d, center_change:%f,delta_pc is %f, loss:$ %f\n", loop, center_change_norm, delta, loss);
//     } while ((center_change_norm) > change_center_thres && loop++ < 500);
//     uint32_t relative_data_movement = numObjs*numCoords*(loop+1)*32;
//     printf("relative_data_movement:*# %d\n", relative_data_movement);
// 	//Clean temp arrays
// 	free (newClusterSize);
// 	free (newClusters);
// }

