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

#ifndef _COYOTE_CGPU_HPP_
#define _COYOTE_CGPU_HPP_

#ifdef EN_GPU

#include <cstddef>
#include <iostream>
#include <stdexcept>

#include <hsa.h>
#include <hip/hip_runtime.h>
#include <hsa/hsa_ext_amd.h>

namespace coyote {

/**
 * @brief Parameters for obtaining region information.
 */
struct get_region_info_params {
    hsa_region_t * region; /**< Pointer to the HSA region. */
    size_t desired_allocation_size; /**< Desired allocation size. */
    hsa_agent_t* agent; /**< Pointer to the HSA agent. */
    bool* taken; /**< Indicates if the region is taken. */
};

/**
 * @brief Information about the GPU.
 */
typedef struct {
    hsa_agent_t gpu_device; /**< HSA GPU device. */
    get_region_info_params* information; /**< Pointer to region information parameters. */
    int requested_gpu; /**< Requested GPU index. */
    int counter_gpu = { 0 }; /**< Counter for GPUs. */
    bool gpu_set; /**< Indicates if the GPU is set. */
} GpuInfo;

/**
 * @brief Callback for HSA routine. Determines if a memory region can be used for a given memory allocation size.
 * 
 * @param region The HSA region to check.
 * @param data Pointer to the region information parameters.
 * @return hsa_status_t Status of the operation.
 */
hsa_status_t get_region_info(hsa_region_t region, void* data);

/**
 * @brief Callback for HSA routine. Determines if the given agent is of type HSA_DEVICE_TYPE_GPU.
 * 
 * @param agent The HSA agent to check.
 * @param data Pointer to the GPU information.
 * @return hsa_status_t Status of the operation.
 */
hsa_status_t find_gpu(hsa_agent_t agent, void *data);

}

// Function added for FPGA-Register Programming
static hsa_status_t find_gpu_noAlloc(hsa_agent_t agent, void *data) {

  if (data == NULL) {
    return HSA_STATUS_ERROR_INVALID_ARGUMENT;
  }
  coyote::GpuInfo *info = reinterpret_cast<coyote::GpuInfo *>(data);
  std::cout << "GPU counter value: " << info->counter_gpu << std::endl;

  hsa_device_type_t device_type;
  hsa_status_t stat =
      hsa_agent_get_info(agent, HSA_AGENT_INFO_DEVICE, &device_type);
  if (stat != HSA_STATUS_SUCCESS) {
    return stat;
  }
  if (device_type == HSA_DEVICE_TYPE_GPU) {
    if (info->counter_gpu == info->requested_gpu) {

      *((hsa_agent_t *)data) = agent;
      char name[64] = {0};
      stat = hsa_agent_get_info(agent, HSA_AGENT_INFO_NAME, name);
      std::cout << "GPU found: " + std::string(name);
    }
    info->counter_gpu++;
  }
  return HSA_STATUS_SUCCESS;
}

#endif

#endif // _COYOTE_CGPU_HPP_