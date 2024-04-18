#include <math.h>

#include "cDefs.hpp"
#include "cTask.hpp"

#include <vector>
#include <chrono>
#include <sys/time.h>  

using namespace fpga;

void initTrees(uint* trees, int numtrees, int numnodes, int depth);

//
// Util
//

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
