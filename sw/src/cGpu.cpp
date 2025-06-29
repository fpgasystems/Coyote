#include "cGpu.hpp"

#ifdef EN_GPU

namespace coyote {

hsa_status_t get_region_info(hsa_region_t region, void* data) {
    struct get_region_info_params * params = (struct get_region_info_params *) data;
    
    size_t max_size = 0;
    int value = hsa_region_get_info(region, HSA_REGION_INFO_ALLOC_MAX_SIZE , &max_size);
    uint32_t info_size;
    value = hsa_region_get_info(region, HSA_REGION_INFO_SIZE, &info_size);
    char name[64];
    int stat = hsa_agent_get_info(*params->agent, HSA_AGENT_INFO_NAME, name);
    if(!*params->taken && max_size > params->desired_allocation_size && info_size > params->desired_allocation_size ) {
        *params->region = region;
        *params->taken = true;
    }
    return HSA_STATUS_SUCCESS;
}

hsa_status_t find_gpu(hsa_agent_t agent, void *data) {
    GpuInfo *info = (GpuInfo *) data;
    
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
            std::cout << "GPU device found numa ID: " << NumaID << ", requested ID: " << info->requested_gpu << std::endl;
            info->gpu_device = agent;
            *info->information->agent = agent;

            stat = hsa_agent_iterate_regions(agent, get_region_info, info->information); 
            if (stat != HSA_STATUS_SUCCESS) {
                return stat;
            }
            get_region_info_params infos = *info->information;
            stat = (infos.region->handle == 0) ? HSA_STATUS_ERROR : HSA_STATUS_SUCCESS;
            if(stat != HSA_STATUS_SUCCESS) {
                throw std::runtime_error("ERROR: Insufficient memory on the GPU");
            }

            info->gpu_set = true;
        } 
        info->counter_gpu++;
    }

    return HSA_STATUS_SUCCESS;
}

}

#endif
