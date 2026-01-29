/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <coyote/cGpu.hpp>

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
