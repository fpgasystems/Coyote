#include <iostream>
#include <string>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <cstring>

#include "cProcess.hpp"

using namespace fpga;

void initData(float* data, uint NUM_FEATURES, uint numtuples);
void initTrees(uint* trees, int numtrees, int numnodes, int depth);

/* Def params */
constexpr auto const targetRegion = 0;

/**
 * @brief Decision tree example
 * 
 */
int main()
{
    uint64_t *tMem, *dMem, *oMem;
    uint64_t n_trees_pages, n_data_pages, n_result_pages;

    //////////////////////////////////////////////////////////////////////////////////////////
    // Parameters
    int NUM_TUPLES = 128 * 1024; //atoi(argv[1]);// atoi(argv[1]);
    int NUM_TREES = 109; //atoi(argv[2]);// atoi(argv[1]);
    int DEPTH = 5; //atoi(argv[3]);// atoi(argv[1]);
    int NUM_FEATURES = 25;// atoi(argv[3]);

    int result_size = 4 * NUM_TUPLES;
    int data_size = NUM_FEATURES * NUM_TUPLES * 4;

    n_data_pages = data_size/hugePageSize   + ((data_size%hugePageSize > 0)? 1 : 0);
    n_result_pages = result_size/hugePageSize + ((result_size%hugePageSize > 0)? 1 : 0);

    uint outputNumCLs = result_size/64 + ((result_size%64 > 0)? 1 : 0);

    unsigned char puTrees = NUM_TREES/28 + ((NUM_TREES%28 == 0)? 0 : 1);

    int numnodes = pow(2, DEPTH) - 1;
    int tree_size = 2*(pow(2,DEPTH-1) - 1) + 10*pow(2,DEPTH-1) + 1;
    tree_size = tree_size + ( ((tree_size%16) > 0)? 16 - (tree_size%16) : 0);

    int trees_size = tree_size*NUM_TREES*4; // atoi(argv[1]);

    n_trees_pages = trees_size/hugePageSize + ((trees_size%hugePageSize > 0)? 1 : 0);

    short lastOutLineMask = ((NUM_TUPLES%16) > 0)? 0xFFFF << (NUM_TUPLES%16) : 0x0000;

    //////////////////////////////////////////////////////////////////////////////////////////
    // Acquire a region
    cProcess cproc(targetRegion, getpid());

    // Allocate Trees Memory
    tMem = (uint64_t*) cproc.getMem({CoyoteAlloc::HOST_2M, (uint32_t)n_trees_pages});
    dMem = (uint64_t*) cproc.getMem({CoyoteAlloc::HOST_2M, (uint32_t)n_data_pages});
    oMem = (uint64_t*) cproc.getMem({CoyoteAlloc::HOST_2M, (uint32_t)n_result_pages});
    
    cout << "Trees  memory mapped at: " << tMem << endl;
    cout << "Data   memory mapped at: " << dMem << endl;
    cout << "Result memory mapped at: " << oMem << endl;
    //////////////////////////////////////////////////////////////////////////////////////////
    // initialize trees/data
    initData(((float*)(dMem)), NUM_FEATURES, NUM_TUPLES);

    initTrees(((uint*)(tMem)), NUM_TREES, numnodes, DEPTH);

    //////////////////////////////////////////////////////////////////////////////////////////
    // Set paprameters
    cproc.setCSR(NUM_FEATURES,     1);
    cproc.setCSR(DEPTH,            2);
    cproc.setCSR(puTrees,          3);
    cproc.setCSR(outputNumCLs,     4);
    cproc.setCSR(lastOutLineMask,  5);
    cproc.setCSR(0x1, 0); // ap_start

    // Push trees to the FPGA, blocking, returns when all trees have been streamed to the FPGA
    cproc.invoke({CoyoteOper::READ, (void*)tMem, (uint32_t)trees_size});

    // Start measuring
    auto begin_time = chrono::high_resolution_clock::now();

    // Stream data into the FPGA, non-blocking, initiate transfer in both directions (results writen back)
    cproc.invoke({CoyoteOper::READ, (void*)dMem, (uint32_t)data_size, true, false});

    // Write results from the FPGA as they come, blocking, returns when all results have been writen to the host
    cproc.invoke({CoyoteOper::WRITE, (void*)oMem, (uint32_t)result_size});

    auto end_time = chrono::high_resolution_clock::now();
    double time = chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
    std::cout << dec << "\nTime: " << time << " us" << std::endl;
    double throughput = (NUM_TUPLES / time);
    std::cout << dec << "\033[31m\e[1mTHROUGHPUT\033[0m\e[0m: " << throughput << " MT/s" << std::endl << std::endl;

    return EXIT_SUCCESS;
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
uint find_node_index(uint nd, uint* indexes, uint* pnodes)
{
    int parent = nd/2;

    if (nd%2 != 0)      return indexes[parent] + 1;
    else                return indexes[parent-1] + pnodes[parent-1] + 1;

    return 0;
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
uint find_depth(uint nd, uint depth)
{
    uint currLevel = depth -1;

    while(1)
    {
        int nd1 = pow(2, currLevel) - 1;

        if (nd >= nd1)  return currLevel;
        else            currLevel = currLevel - 1;
    }
    return 0;
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
void initTrees(uint* trees, int numtrees, int numnodes, int depth)
{
  uint node_t;
  uint curr_tree_offset = 0;

  uint* nodes_ids  = new uint[numnodes];
  uint* nodes_size = new uint[numnodes];
  uint* indexes    = new uint[numnodes];
  uint* pnodes     = new uint[numnodes];

  // set root
  nodes_ids[0]  = 0;
  nodes_size[0] = 2;
  indexes[0]    = 0;
  pnodes[0]     = numnodes/2;

  int lastLevelNodeID = numnodes/2;

  for (int i = 1; i < numnodes; ++i)
  {
      int idx = find_node_index(i, indexes, pnodes);
      nodes_ids[idx]   = i;
      nodes_size[idx]  = (i < lastLevelNodeID)? 2 : 10;
      indexes[i]       = idx;

      uint ndLevel = find_depth(i, depth);
      pnodes[i]    = pow(2, (depth-1-ndLevel) ) - 1;
  }

  for(int i = 0; i < numnodes; i++)  printf("(%d, %d)", nodes_ids[i], nodes_size[i]);
  printf("\n");

  delete [] pnodes;
  delete [] indexes;

  //
  for (int i = 0; i < numtrees; ++i)
  {
    // initialize tree i
      uint tree_i[4096];
      uint node_off = 0;
    for (int j = 0; j < numnodes; ++j)
    {
      // initialize node j;
      // Node type
      node_t = 0;

      uint op_type       = (nodes_ids[j] >= lastLevelNodeID)? 3 : (i%2 == 0)? 0  : 2;
      uint left_child    = (nodes_ids[j] >= lastLevelNodeID)? 0 : 1;
      uint right_child   = (nodes_ids[j] >= lastLevelNodeID)? 0 : 1;
      uint findex        = nodes_ids[j]%25;
      uint split_dir     = 2;

      uint rc_id = nodes_ids[j]*2 + 2;

      uint rc_off = 0;
      for (int f = j+1; f < numnodes; ++f)
      {
        if (nodes_ids[f] != rc_id) rc_off += nodes_size[f];
        else                       break;
      }

      uint rchild_offset = (nodes_ids[j] >= lastLevelNodeID)? 0 : rc_off;

      node_t = (node_t & 0xFFFFFFFC) | ((op_type       << 0)  & 0x00000003);
      node_t = (node_t & 0xFFFFFFFB) | ((left_child    << 2)  & 0x00000004);
      node_t = (node_t & 0xFFFFFFF7) | ((right_child   << 3)  & 0x00000008);
      node_t = (node_t & 0xFFFFF00F) | ((findex        << 4)  & 0x00000FF0);
      node_t = (node_t & 0xFFFF0FFF) | ((split_dir     << 12) & 0x0000F000);
      node_t = (node_t & 0x0000FFFF) | ((rchild_offset << 16) & 0xFFFF0000);

      tree_i[node_off] = node_t;
      node_off        += 1;

      // split value/set
      float sval = 1.5;
      if (nodes_ids[j] < lastLevelNodeID)
      {
        if (i%2 == 0)   // split value
        {
          memcpy( &(tree_i[node_off]), &sval, 4);
        }
        else     // small split Set
        {
          tree_i[node_off] = 0xAAAAAAAA;
        }
        node_off += 1;
      }
      else
      {
        // large split set offset and length
        tree_i[node_off] = 0x00000006;
        node_off        += 1;
        //
        float val = 2.5;
        memcpy( &(tree_i[node_off]), &val, 4);
        val = 0.5;
        memcpy( &(tree_i[node_off+1]), &val, 4);

        for (int s = 0; s < 6; ++s)      // large split set words
        {
          tree_i[node_off + 2 + s] = 0x55555555;
        }

        node_off += 8;
      }

    }
    // trees
    trees[curr_tree_offset] = node_off;
    for (uint32_t t = 0; t < node_off; ++t)
    {
      trees[curr_tree_offset+1+t] = tree_i[t];
    }

    curr_tree_offset += node_off + 1;

    printf("Tree Size = %d\n", curr_tree_offset);

    curr_tree_offset = curr_tree_offset + (((curr_tree_offset%16) != 0)? 16 - (curr_tree_offset%16) : 0);
  }

  //
  delete [] nodes_ids;
  delete [] nodes_size;

  printf("Initialization done!\n"); fflush(stdout);
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
void initData(float* data, uint NUM_FEATURES, uint numtuples)
{
    for (int i = 0; i < numtuples; ++i)
    {
       for (int j = 0; j < NUM_FEATURES; ++j)
       {
          data[i*NUM_FEATURES + j] = ((float)(i+1))/((float)(j+i+1));
       }
    }
}
