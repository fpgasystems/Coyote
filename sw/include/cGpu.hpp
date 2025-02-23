#pragma once

#include "cDefs.hpp"

#ifdef EN_GPU

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

#include <hip/hip_runtime.h>
#include <hsa/hsa_ext_amd.h>
#include <hsa.h>
#include <hsa/hsa_ext_finalize.h>
#include <hsakmt/hsakmt.h>

namespace coyote {

struct get_region_info_params {
    hsa_region_t * region;
    size_t desired_allocation_size;
    hsa_agent_t* agent;
    bool* taken;
};

struct GpuInfo {
    hsa_agent_t gpu_device;
    get_region_info_params* information;
    int requested_gpu; 
    int counter_gpu = { 0 };
    bool gpu_set; 
};

/**
 * @brief Print region info
 * 
 */
static void print_info_region(hsa_region_t* region){
    hsa_region_segment_t segment;
    hsa_region_get_info(*region, HSA_REGION_INFO_SEGMENT, &segment); 
    uint32_t flags;
    hsa_region_get_info(*region, HSA_REGION_INFO_GLOBAL_FLAGS,&flags); // Giuseppe: here I can request several info
    uint32_t info_size;
    hsa_region_get_info(*region, HSA_REGION_INFO_SIZE,&info_size ); // Giuseppe: here I can request several info
    size_t max_size = 0;
    hsa_region_get_info(*region, HSA_REGION_INFO_ALLOC_MAX_SIZE , &max_size); // Giuseppe: here I can request several info
    uint32_t max_pvt_wg;
    hsa_region_get_info(*region, HSA_REGION_INFO_ALLOC_MAX_PRIVATE_WORKGROUP_SIZE  , &max_pvt_wg); // Giuseppe: here I can request several info
    bool check;
    hsa_region_get_info(*region, HSA_REGION_INFO_RUNTIME_ALLOC_ALLOWED, &check); // Giuseppe: here I can request several info
    size_t runtime_granule;
    hsa_region_get_info(*region, HSA_REGION_INFO_RUNTIME_ALLOC_GRANULE, &runtime_granule); // Giuseppe: here I can request several info
    size_t runtime_alignment;
    hsa_region_get_info(*region, HSA_REGION_INFO_RUNTIME_ALLOC_ALIGNMENT , &runtime_alignment); // Giuseppe: here I can request several info

    std::cout<<"HSA_REGION_INFO_SEGMENT: "<<segment<<std::endl;
    std::cout<<"HSA_REGION_INFO_GLOBAL_FLAGS Flags: "<<flags<<std::endl;
    std::cout<<"HSA_REGION_INFO_SIZE: "<<info_size<<std::endl;
    std::cout<<"HSA_REGION_INFO_ALLOC_MAX_SIZE : "<<max_size<<std::endl;
    std::cout<<"HSA_REGION_INFO_ALLOC_MAX_PRIVATE_WORKGROUP_SIZE : "<<max_pvt_wg<<std::endl;
    std::cout<<"HSA_REGION_INFO_RUNTIME_ALLOC_ALLOWED : "<<check<<std::endl;
    std::cout<<"HSA_REGION_INFO_RUNTIME_ALLOC_GRANULE: "<<runtime_granule<<std::endl;
    std::cout<<"HSA_REGION_INFO_RUNTIME_ALLOC_ALIGNMENT: "<<runtime_alignment<<std::endl;
}

/**
 * @brief Callback for HSA routine. It determines if a memory region can be used for a given memory allocation size.
 * 
 */
static hsa_status_t get_region_info(hsa_region_t region, void* data) {
    struct get_region_info_params * params = (struct get_region_info_params *) data;
    
    size_t max_size = 0;
    int value = hsa_region_get_info(region, HSA_REGION_INFO_ALLOC_MAX_SIZE , &max_size); // Giuseppe: here I can request several info
    //std::cout<<"Giuseppe: Check of getInfo for HSA_REGION_INFO_ALLOC_MAX_SIZE: " << value << std::endl;
    uint32_t info_size;
    value = hsa_region_get_info(region, HSA_REGION_INFO_SIZE,&info_size ); // Giuseppe: here I can request several info
    //std::cout<<"Giuseppe: Check of getInfo for HSA_REGION_INFO_SIZE: " << value << std::endl;
    //std::cout << "Giuseppe: Value of Infosize: " << info_size << std::endl;
    //std::cout << "Giuseppe: Max Allocation Size: " << max_size << std::endl;
    //std::cout << "Desidered Allocation Size: " << params->desired_allocation_size << std::endl;
    char name[64];
    int stat = hsa_agent_get_info(*params->agent, HSA_AGENT_INFO_NAME, name);
    if(!*params->taken && max_size > params->desired_allocation_size && info_size > params->desired_allocation_size )
      {
          //std::cout << "Belonging to the agent: " << name << std::endl;
          //print_info_region(&region);

    // if(max_size < params->desired_allocation_size) {
    //     return HSA_STATUS_ERROR;
    // }

    //TODO: check on memory size. Currently HSA_REGION_INFO_ALLOC_MAX_SIZE > HSA_REGION_INFO_SIZE for both GPUs
        *params->region = region;
        *params->taken = true;
        //std::cout<<"Returning a region"<<std::endl;

      }
  
    return HSA_STATUS_SUCCESS;
}

/**
 * @brief Callback for HSA routine. It determines if the given agent is of type HSA_DEVICE_TYPE_GPU
 * and sets the value of data to the agent handle if it is.
 * 
 */
static hsa_status_t find_gpu(hsa_agent_t agent, void *data) {
    if (data == nullptr) {
        return HSA_STATUS_ERROR_INVALID_ARGUMENT;
    }
    GpuInfo* info = reinterpret_cast<GpuInfo*>(data);
    
    hsa_device_type_t device_type;
    hsa_status_t stat = hsa_agent_get_info(agent, HSA_AGENT_INFO_DEVICE, &device_type);
    if (stat != HSA_STATUS_SUCCESS) {
        return stat;
    }

    uint32_t NumaID; 
    stat = hsa_agent_get_info(agent, HSA_AGENT_INFO_NODE, &NumaID);
    if (stat != HSA_STATUS_SUCCESS) {
        return stat;
    }

    if(device_type == HSA_DEVICE_TYPE_GPU) {
        if(info->counter_gpu == info->requested_gpu) {
            std::cout<<"GPU device found numa ID: " << NumaID << ", requested ID: " << info->requested_gpu << std::endl;
            info->gpu_device = agent;
            *info->information->agent = agent;

            stat = hsa_agent_iterate_regions(agent, get_region_info, info->information); 
            if (stat != HSA_STATUS_SUCCESS) {
                return stat;
            }
            get_region_info_params infos = *info->information;
            stat = (infos.region->handle == 0) ? HSA_STATUS_ERROR : HSA_STATUS_SUCCESS;
            if(stat != HSA_STATUS_SUCCESS) {
                throw std::runtime_error("Insufficient memory on the GPU!");
            }

            info->gpu_set = true;
        } 
        info->counter_gpu++;
    }

    return HSA_STATUS_SUCCESS;
}


}

#endif
