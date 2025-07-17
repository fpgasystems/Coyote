/**
 * Copyright (c) 2021, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
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
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <any>
#include <assert.h>
#include <boost/program_options.hpp>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <errno.h>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <limits>
#include <malloc.h>
#include <mutex>
#include <netdb.h>
#include <signal.h>
#include <sstream>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <syslog.h>
#include <thread>
#include <unistd.h>
#include <unordered_map>
#include <vector>
#include <wait.h>

#include "cThread.hpp"

using namespace std;
using namespace coyote;

constexpr auto const defRunHLL = false;
constexpr auto const defRunDtrees = false;
constexpr auto const defNTuples = 128 * 1024;
constexpr auto const defNFeatures = 5;

#define DEFAULT_VFPGA_ID 6

/**
 * @brief Atomic store operation for 32-bit values
 *
 * This function performs an atomic store operation on a 32-bit value
 * using the HIP atomic API. It ensures that the store operation is
 * performed with sequential consistency and is visible across all
 * threads and devices in the system.
 *
 * @param DST Pointer to the destination address where the value will be stored
 * @param SRC The source value to be stored at the destination address
 * @return void
 *
 */
#define STORE(DST, SRC)                                                        \
  __hip_atomic_store((DST), (SRC), __ATOMIC_SEQ_CST, __HIP_MEMORY_SCOPE_SYSTEM)

/**
 * @brief Set register programming
 *
 * @param ctrl_reg Pointer to the control register
 * @param val Value to be written
 * @param offs Offset in the control register array
 */
__device__ inline auto setCSR_Atomic_SEQ(volatile uint64_t *ctrl_reg,
                                         uint64_t val, uint32_t offs) {

  STORE(&ctrl_reg[offs], val);
  asm volatile("s_waitcnt vmcnt(0)"); // Ensure visibility of the store
}

/**
 * @brief Kernel to test the Register Programming
 */
__global__ void launch_basic_test(volatile uint64_t *ctrl_reg) {

  setCSR_Atomic_SEQ(ctrl_reg, 0xbbbbbbbb, 1);
  setCSR_Atomic_SEQ(ctrl_reg, 0xcccccccc, 2);
  setCSR_Atomic_SEQ(ctrl_reg, 0xaaaaaaaa, 0);
  setCSR_Atomic_SEQ(ctrl_reg, 0xffffffff, 0);
}

/**
 * @brief Main
 *
 */

int main(int argc, char *argv[]) {
  /* Args */
  boost::program_options::options_description programDescription("Options:");
  programDescription.add_options()(
      "device,d", boost::program_options::value<uint32_t>(), "Target device")(
      "vfid,i", boost::program_options::value<uint32_t>(), "Target vFPGA");
  programDescription.add_options()("help,h",
                                   "Print this help message and exit");
  boost::program_options::variables_map commandLineArgs;
  boost::program_options::store(boost::program_options::parse_command_line(
                                    argc, argv, programDescription),
                                commandLineArgs);
  boost::program_options::notify(commandLineArgs);

  uint32_t cs_dev = 0;
  uint32_t vfid = 0;

  if (commandLineArgs.count("device") > 0)
    cs_dev = commandLineArgs["device"].as<uint32_t>();
  if (commandLineArgs.count("vfid") > 0)
    vfid = commandLineArgs["vfid"].as<uint32_t>();

  std::unique_ptr<cThread<std::any>> coyote_thread(
      new cThread<std::any>(0, getpid(), vfid));

  printf("FPGA REGISTER PROGRAMMING - EXAMPLE \n");
  int device_id = 0;
  int gpu_id = 0;
  int target_region = 0;

  int err_int = hipSetDevice(gpu_id);
  hipDeviceProp_t props;
  hipGetDeviceProperties(&props, gpu_id);
  std::cout << "Device "
            << ": " << props.name << std::endl;
  if (err_int != 0) {
    std::cout << "Value of err: " << err_int << std::endl;
    throw std::runtime_error("Wrong GPU selection!");
  }
  void *ctrl_reg = coyote_thread->get_ctrl_reg(gpu_id);

  std::cout << "Insert a value to start the GPU kernel execution" << std::endl;
  int input = 0;
  std::cin >> input;
  printf("Going to launch the kernel:\n");
  hipLaunchKernelGGL(launch_basic_test, dim3(1), dim3(1), 0, 0,
                     (volatile uint64_t *)ctrl_reg);
  hipDeviceSynchronize();
  hipError_t val = hipGetLastError();

  printf("Value of the last error: %d \n", val);
  std::cout << "Insert a value to end the software" << std::endl;
  input = 0;

  // this stalls the kernel giving time to set ILA, if existing
  std::cin >> input;
  std::cout << "register written" << std::endl;
}
