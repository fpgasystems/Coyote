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

// void compute_low_precision_kmeans(int precision, uint32_t* objects, uint32_t* clusters_ref, int numObjs, int numClusters, int numCoords, int max_iter, bool user_specify_precision);
// void low_precision_kmeans(int numObjs, int numClusters, int numCoords, int* member_ref, uint32_t* newClusterSize, uint64_t* newClusters, uint32_t* objects, uint32_t* clusters_ref, int max_loop, int precision, int* total_loop);
// void printCentroids(uint32_t *centroid, uint32_t numClusters, uint32_t numCoords, uint32_t number_of_iteration);
// void normalization_scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features ,float* dr_a_min, float* dr_a_max);
// void initial_centroids(int numClusters, int numCoords, int numObjs, uint32_t* cluster, uint32_t* objects);
// void convert_precision(int precision, int nfeatures, int npoints, uint32_t* features, uint32_t* low_precision_feature);

// float get_sse(int numObjs, int numClusters, int numCoords, float * objects, float * clusters_ref);
// void convert_precision_de_normalization (int nfeatures, int npoints, int precision, uint32_t* low_precision_feature, float* denomalized_features, float* dr_a_min, float* dr_a_max);
// void normalization(int nfeatures, int npoints, float* features, float* normalized_features);