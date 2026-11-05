/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
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

#ifndef COYOTE_GA_HPP
#define COYOTE_GA_HPP

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <coyote/cThread.hpp>
#include "cvrp_types.hpp"
#include "ga_engine.hpp"
#include "batch_job.hpp"

namespace coyote_ga {

constexpr unsigned int kNumVfpgas = 2;

// Control register indices matching the AXI4-Lite control register map generated
// by Vitis HLS for the scalar configuration arguments of the processing_node kernel.
// Coyote CSRs are 64-bit wide, so the setCSR index equals byte offset / 8.
constexpr uint32_t CSR_CONTROL                 = 0x00;
constexpr uint32_t CSR_CONTROL_START           = 0x01;
constexpr uint32_t CSR_NUM_INDIVIDUALS         = 0x10 / 8;
constexpr uint32_t CSR_NUM_CITIES              = 0x18 / 8;
constexpr uint32_t CSR_VEHICLE_CAPACITY        = 0x20 / 8;
constexpr uint32_t CSR_INIT_CITY_CACHE         = 0x28 / 8;
constexpr uint32_t CSR_TWO_OPT_K               = 0x30 / 8;
constexpr uint32_t CSR_TWO_OPT_ENABLE_PRECHECK = 0x38 / 8;
constexpr uint32_t CSR_SEED                    = 0x40 / 8;
constexpr uint32_t CSR_CROSSOVER_PROB          = 0x48 / 8;
constexpr uint32_t CSR_MUTATION_PROB           = 0x50 / 8;

/**
 * Kernel scalar registers configuration struct.
 */
struct KernelConfig {
    uint32_t num_individuals;
    uint32_t num_cities;
    uint32_t vehicle_capacity;
    int two_opt_k;
    bool two_opt_enable_precheck;
    uint32_t seed;
    int crossover_prob;
    int mutation_prob;
};

/**
 * High-level application configuration embedding the existing AsyncGAParams.
 */
struct CoyoteAppConfig {
    AsyncGAParams ga_params;
    std::size_t population_size_multiplier;
    int two_opt_k;
    bool two_opt_enable_precheck;
    int crossover_prob;
    int mutation_prob;
    bool smoke_test;
    std::string vrp_file;
    std::string output_file;
};

/**
 * Constructs a KernelConfig from the problem instance and application configuration.
 */
KernelConfig make_kernel_config(
    const ProblemInstance &problem,
    const CoyoteAppConfig &config,
    uint32_t vfpga_seed,
    uint32_t num_ind
);

/**
 * Aligns and allocates hugepage memory via coyote::cThread.
 */
std::uint8_t *allocate_buffer(coyote::cThread &coyote_thread, std::size_t bytes);

/**
 * Programs all 8 scalar configuration CSRs on the given vFPGA.
 */
void program_kernel_registers(coyote::cThread &thread, const KernelConfig &config);

/**
 * Validates that ALL 8 scalar configuration CSRs were correctly programmed.
 * Returns true if all match, or false with diagnostic mismatch logs.
 */
bool validate_kernel_registers(coyote::cThread &thread, unsigned int vfid, const KernelConfig &config);

/**
 * Programs and validates all kernel configuration registers.
 * Throws std::runtime_error on mismatch.
 */
void program_and_validate_kernel(coyote::cThread &thread, unsigned int vfid, const KernelConfig &config);

/**
 * Initializes the node cache on the specified vFPGA beforehand via Stream 0.
 */
void initialize_node_cache(coyote::cThread &thread, unsigned int vfid, const ProblemInstance &problem);

/**
 * Executes a dual-stream (Stream 0 & Stream 1) hardware transfer and waits for completion.
 */
void execute_dual_stream_transfer(
    coyote::cThread &thread,
    const uint8_t *src_0,
    const uint8_t *src_1,
    uint8_t *dst_0,
    uint8_t *dst_1,
    uint32_t len,
    uint32_t seed = 0,
    bool set_seed = false
);

/**
 * Runs a single generation smoke test on a specific vFPGA and verifies fitness.
 */
bool run_smoke_test(unsigned int vfid, const ProblemInstance &problem, const CoyoteAppConfig &config);

/**
 * Runs smoke test across all available vFPGAs.
 */
bool run_smoke_tests_all(const ProblemInstance &problem, const CoyoteAppConfig &config);

/**
 * Executes the full asynchronous pipelined GA across all available vFPGAs.
 */
GASummary run_pipelined_ga(const ProblemInstance &problem, CoyoteAppConfig &config);

} // namespace coyote_ga

#endif // COYOTE_GA_HPP
