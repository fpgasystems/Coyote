

// void initial_centroids(int numClusters, int numCoords, int numObjs, float* cluster, float* objects);
// void compute_low_precision_kmeans(int precision, float* float_objects, float* clusters_ref, int* member_ref, int numObjs, int numClusters, int numCoords, int iter, bool user_specify_precision, float threshold);
// void low_precision_kmeans(int numObjs, int numClusters, int numCoords, int* member_ref, float* newClusterSize, float* newClusters, float* objects, float* clusters_ref, int max_loop, int precision, float* delta, float threshold, int* total_loop);
// void compute_reference_kmeans(float* objects, float* clusters_ref, int* member_ref, int numObjs, int numClusters, int numCoords, int iter, float threshold);
// float get_change_center_thres (float* features, int nfeatures, int npoints);

#ifndef CLASSIC_KMEANS_H
#define CLASSIC_KMEANS_H

void compute_kmeans(uint32_t* objects, uint32_t* clusters_ref, int numObjs, int numClusters, int numCoords, int max_iter, bool user_specify_precision);
void run_kmeans(int numObjs, int numClusters, int numCoords, int* member_ref, uint32_t* newClusterSize, uint64_t* newClusters, uint32_t* objects, uint32_t* clusters_ref, int max_loop, int* total_loop);
void printCentroids(uint32_t*centroid, uint32_t numClusters, uint32_t numCoords, uint32_t number_of_iteration);
void normalization_scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features ,float* dr_a_min, float* dr_a_max);
void initial_centroids(int numClusters, int numCoords, int numObjs, uint32_t* cluster, uint32_t* objects);
void convert_precision(int precision, int nfeatures, int npoints, uint32_t* features, uint32_t* low_precision_feature);

float get_sse(int numObjs, int numClusters, int numCoords, float * objects, float * clusters_ref);
void descale_normalization (int nfeatures, int npoints, uint32_t* low_precision_feature, float* denomalized_features, float* dr_a_min, float* dr_a_max);
void normalization(int nfeatures, int npoints, float* features, float* normalized_features);
void scale(int nfeatures, int npoints, float* features, uint32_t* scaled_unsigned_features,float* dr_a_min, float* dr_a_max);

#endif