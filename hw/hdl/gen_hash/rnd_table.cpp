/**
  * Copyright (c) 2021, Systems Group, ETH Zurich
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
#include <iostream>
#include <random>
#include <string>
#include <fstream>
#include <math.h>

//
// Random hash function
//
int main(int argc, char *argv[])
{
    if (argc != 5) {
        std::cerr << "ERROR:  number of arguments not correct\n";
        std::cerr << "Usage generate_random_table <number of tables> <block size> <length of key> <length of hash>\n";
        return -1;
    }

    int n_tables = atoi(argv[1]);
    int n_blocks = atoi(argv[2]);
    int key_size = atoi(argv[3]);
    int table_size = atoi(argv[4]);

    std::string fileName("tabulation_table.sv");
    std::ofstream outfile;
    outfile.open(fileName.c_str());

    if(!outfile) {
        std::cerr << "Could not open output file";
        return -1;
    }

    int order = log2(n_blocks);

    std::cout << log2(n_blocks) << std::endl;

    uint32_t mak_key = pow(2, table_size) - 1;
    std::default_random_engine generator;
    std::uniform_int_distribution<int> distribution(0, mak_key);

   for (int i = 0; i < n_tables; i++)
   {
      outfile << "//\n// Table: " << i << "\n//\n";
      outfile << "logic [" << n_tables << "-1:0][" << n_blocks << "-1:0][" << key_size/order << "-1:0][" << table_size << "-1:0] " << "hash_lup;\n";
      for (int j = 0; j < n_blocks; j++)
      {
         outfile << "// Block: " << j << "\n";
         for (int k = 0; k < key_size; k+= order)
         {
            int rnd_val = distribution(generator);
            outfile << "assign hash_lup[" << i << "][" << j << "][" << (k >> order-1) << "] = " << rnd_val << ";\n";
         }
         outfile << "\n";
      }
   }

   outfile.close();
   std::cout << "Table succesfully generated" << std::endl;
   return 0;
}
