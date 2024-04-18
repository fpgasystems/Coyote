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

#include "utils.hpp"
#include <limits>
#include <math.h>
#include <stdlib.h>     

using namespace std;

void readFloatData(char* filename, float* points, uint32_t size, uint32_t dimensions)
{
   std::ifstream inputFile(filename);
   if (!inputFile) {
      std::cerr << "Coult no open file: " << filename << std::endl;
      return;
   }

   std::string line;
   uint32_t idx = 0;
   while(getline(inputFile, line)) {
      std::stringstream ss(line);
      std::string value;
      bool isFirst = true;
      while(getline(ss, value, ',')) {
         std::stringstream vs(value);
         float v = 0.0;
         vs >> v;
         if (isFirst) {
            isFirst = false;
            continue;
         }
         points[idx] = v;
         idx++;
      }
   }

   inputFile.close();
}

void readFixData(char* filename, uint32_t* points, uint32_t size, uint32_t dimensions, uint32_t fixpoint)
{
   std::ifstream inputFile(filename);
   if (!inputFile) {
      std::cerr << "Coult no open file: " << filename << std::endl;
      return;
   }

   std::string line;
   uint32_t idx = 0;
   while(getline(inputFile, line)) {
      std::stringstream ss(line);
      std::string value;
      bool isFirst = true;
      while(getline(ss, value, ',')) {
         std::stringstream vs(value);
         float v = 0.0;
         vs >> v;
         if (isFirst) {
            isFirst = false;
            continue;
         }
         points[idx] = (uint32_t) (v*fixpoint);
         idx++;
      }
   }

   inputFile.close();
}

void read_input(const char *filename, int nclusters, int nfeatures, int npoints, float* features, int non_padding_features)
{
    int ret_val;
   printf("Read input data from file\n");
    float temp;
    int i;

    FILE *fp = fopen(filename, "r");
    if (fp==NULL)
    {
      printf("cannot find file\n");
    }

    for(i = 0; i < npoints; i++){
	for(int j =0; j< non_padding_features; j++)
        {
	    ret_val = fscanf(fp, "%f", &temp);
            features[i*nfeatures+j] = temp;
    	}
    }

    printf("\nI/O completed\n");
    // printf("\nNumber of objects: %u\n", npoints);
    // printf("Number of features: %u\n", nfeatures);  
    printf("\nFinish file reading\n");
     
}


void data_gen(float* data, uint64_t data_set_size, uint32_t data_dim )
{
    srand(0);
    uint64_t maximum = pow(2,8);
    printf("generated_data:\n");
    for(int data_cnt=0; data_cnt< data_set_size; data_cnt++)
    {
      
      for (int i = 0; i < data_dim; ++i)
      {
        data[data_cnt*data_dim+i]=  rand()%maximum;
        //printf("%f, ",data[data_cnt*data_dim+i]);
      }
    }
    printf("\n");
}


void read_file(float *array,  int N,  int D, const char *filename, bool isBinary){
    FILE *fp;
    int counts = 0;
    int i=0,j=0;
    char line[MAX_LINE_LENGTH];
    char *token=NULL;
    char space[2] = " ";

    fp = fopen(filename,"r");

    if ( fp == NULL ){
        fprintf(stderr, "File '%s' does not exists!", filename);
        exit(1);
    }

    if ( isBinary ){
        // read binary file, everything at once
        counts = fread(array, sizeof(float) * N * D, 1, fp);

        if ( counts == 0 ) {
            fprintf(stderr, "Binary file '%s' could not be read. Wrong format.", filename);
            exit(1);
        }
    }else{
        // processing a text file
        // format: there are D float values each line. Each value is separated by a space character.
        // notice MAX_LINE_LENGTH = 2049
        i = 0;
        while ( fgets ( line, MAX_LINE_LENGTH, fp ) != NULL &&
                i < N ) {


            if ( line[0] != '%'){ // ignore '%' comment char
                token = strtok(line, space);
                j=0;


                while ( token != NULL &&
                        j < D ){
                            
                    array[i*D + j] = atof(token); // 0.0 if no valid conversion
                    token = strtok(NULL, space);
                    j++;
                }
                i++;
            }
        }
    }

    fclose(fp);
}

