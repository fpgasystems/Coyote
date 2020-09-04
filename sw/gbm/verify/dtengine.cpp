

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <malloc.h>
#include <string.h>

using namespace std;
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
    for (uint t = 0; t < node_off; ++t)
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

  printf("initialization done!\n"); fflush(stdout);
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
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////

void dtinfer_sw(uint* trees, void* data, void* res, uint numtuples, uint numtrees, uint num_features)
{
  for(int d = 0; d < numtuples; ++d)
  {
    //printf("process tuple: %d\n", d);
    float    tuple_res        = 0.0;
    uint curr_tree_offset = 0;
    for (int t = 0; t < numtrees; ++t)
    {
      //
      bool     tree_end         = false;
      uint curr_node_offset = 0;
      uint next_node_offset;

      curr_tree_offset += 1;

      //
      while( !tree_end )
      {
        // 
        uint findex        = (trees[curr_tree_offset + curr_node_offset] >> 4)   & 0x000000FF;
        uint optype        = trees[curr_tree_offset + curr_node_offset]          & 0x00000003;
        uint split_dir     = (trees[curr_tree_offset + curr_node_offset] >> 12)  & 0x0000000F;
        bool has_rchild    = ((trees[curr_tree_offset + curr_node_offset] >> 2)  & 0x00000001) == 1;
        bool has_lchild    = ((trees[curr_tree_offset + curr_node_offset] >> 3)  & 0x00000001) == 1;

        uint rchild_offset = ((trees[curr_tree_offset + curr_node_offset] >> 16)  & 0x0000FFFF);

        uint left_offset  = curr_node_offset + 2 + ((has_lchild)? 0 : 1) + ((has_rchild)? 0 : 1);
        uint right_offset = left_offset + rchild_offset; 

        bool go_right = false;

        if (optype == 0)
        {
          float* features = reinterpret_cast<float*>(data);
          float feature_f = features[d*num_features+findex];

          float split_val;
          memcpy( &split_val, &(trees[curr_tree_offset + curr_node_offset+1]), 4);

          go_right = feature_f < split_val;
        }
        else if(optype == 2)
        {
          uint* features = reinterpret_cast<uint*>(data);
          uint feature_i = features[d*num_features+findex];
          uint split_set = trees[curr_tree_offset + curr_node_offset+1];

          go_right = ((feature_i > 31) || (feature_i < 0))? false : (split_set >> feature_i) & 0x00000001;
        }
        else if(optype == 3)
        {
          uint* features      = reinterpret_cast<uint*>(data);
          uint feature_i      = features[d*num_features+findex];
          uint splitset_off   = ((!has_lchild)? 1 : 0) + ((!has_rchild)? 1 : 0);
          uint splitset_start = ((trees[curr_tree_offset + curr_node_offset+1])        & 0x0000FFFF);
          uint splitset_leng  = ((trees[curr_tree_offset + curr_node_offset+1] >> 16)  & 0x0000FFFF);

          uint split_set      = trees[curr_tree_offset + curr_node_offset+2+splitset_off];

          go_right = ((feature_i >= (splitset_start+splitset_leng)) || (feature_i < splitset_start))? false : ((split_set - splitset_start) >> feature_i) & 0x00000001;
        }
        ///////////////////////////////////
        next_node_offset = (go_right)? right_offset : left_offset;

        uint res_offset = (go_right)? ((has_lchild)? 1 : 0) : 0;

        if (go_right)
        {
          //printf("Go Right for tree off: %d, node_off : %d, rchild:%d, res_offset: %d\n", curr_tree_offset, curr_node_offset, has_rchild, res_offset);
          if (!has_rchild)
          {
            tree_end = true;
            float tree_res;
            memcpy( &tree_res, &(trees[curr_tree_offset + curr_node_offset+2+res_offset]), 4);
            //printf("right child tree_res = %.10f\n", tree_res);
            tuple_res += tree_res;
          }
        }
        else 
        {
          //printf("Go Left for tree off: %d, node_off : %d, lchild:%d, res_offset: %d\n", curr_tree_offset, curr_node_offset,has_lchild, res_offset);
          if (!has_lchild)
          {
            tree_end = true;
            float tree_res;
            memcpy( &tree_res, &(trees[curr_tree_offset + curr_node_offset+2+res_offset]), 4);
            //printf("left child tree_res = %.10f\n", tree_res);
            tuple_res += tree_res;
          }
        }
        //
        curr_node_offset = next_node_offset;
      }
      //////////////////////////////////////
      curr_tree_offset += trees[curr_tree_offset-1];

      curr_tree_offset = curr_tree_offset + (((curr_tree_offset%16) != 0)? 16 - (curr_tree_offset%16) : 0);
    }
    (reinterpret_cast<float*>(res))[d] = tuple_res;
  }
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(int argc, char *argv[])
{

    //////////////////////////////////////////////////////////////////////////////////////////
    // Parameters
    int NUM_TUPLES         = 1024; //atoi(argv[1]);// atoi(argv[1]);
    int NUM_TREES          = 109; //atoi(argv[2]);// atoi(argv[1]);
    int DEPTH              = 5; //atoi(argv[3]);// atoi(argv[1]);
    int NUM_FEATURES       = 25;// atoi(argv[3]);

    int result_size        = 4*NUM_TUPLES;
    int data_size          = NUM_FEATURES*NUM_TUPLES*4;

    uint outputNumCLs      = result_size/64 + ((result_size%64 > 0)? 1 : 0);

    unsigned char puTrees  = NUM_TREES/28 + ((NUM_TREES%28 == 0)? 0 : 1);

    int numnodes           = pow(2, DEPTH) - 1;
    int tree_size          = 2*(pow(2,DEPTH-1) - 1) + 10*pow(2,DEPTH-1) + 1;
    tree_size              = tree_size + ( ((tree_size%16) > 0)? 16 - (tree_size%16) : 0);

    int trees_size         = tree_size*NUM_TREES*4; // atoi(argv[1]);

    //////////////////////////////////////////////////////////////////////////////////////////
    // Allocate memory
    uint*  trees           = reinterpret_cast<uint*>(malloc( trees_size ));        
    float* data            = reinterpret_cast<float*>( malloc(data_size ));  
    void*  res             = malloc( result_size );

    //////////////////////////////////////////////////////////////////////////////////////////
    // initialize trees/data
    initData(data, NUM_FEATURES, NUM_TUPLES);

    initTrees(trees, NUM_TREES, numnodes, DEPTH);

    //////////////////////////////////////////////////////////////////////////////////////////
    // run software
    dtinfer_sw(trees, data, res, NUM_TUPLES, 109, NUM_FEATURES);

    //////////////////////////////////////////////////////////////////////////////////////////
    // Printout results
    printf("Obtained Results:\n");
    for (int i = 1; i <= NUM_TUPLES; ++i)
    {
      printf("  %.5f  ", (reinterpret_cast<float*>(res))[i-1] );
      if ( (i%16) == 0 ) printf("\n");
      
    }

    return 1;
}
