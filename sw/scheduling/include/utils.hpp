#ifndef UTILS_HPP
#define UTILS_HPP
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define MAX_LINE_LENGTH 2049

void readFloatData(char* filename, float* points, uint32_t size, uint32_t dimensions);
void readFixData(char* filename, uint32_t* points, uint32_t size, uint32_t dimensions, uint32_t fixpoint);

template <class T>
void printPoints(T* points, uint32_t size, uint32_t dimensions)
{
   T* ptr = points;
   for (uint32_t i = 0; i < size; ++i) {
      std::cout << "point[" << i << "]:";
      for (uint32_t d = 0; d < dimensions; ++d) {
         std::cout << " " << *ptr;
         ptr++;
      }
      std::cout << std::endl;
   }
}

void read_input(const char *filename, int nclusters, int nfeatures, int npoints, float* features);
void data_gen(float* data, uint64_t data_set_size, uint32_t data_dim );
void read_file(float *array,  int N,  int D, const char *filename, bool isBinary);


#endif
