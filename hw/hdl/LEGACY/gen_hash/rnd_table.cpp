/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2021-2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
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
