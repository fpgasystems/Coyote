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

#include "coyote_ga.hpp"

#include <array>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <unistd.h>

#include <coyote/cBench.hpp>
#include "ga_encoding_constants.hpp"
#include "ga_streaming.hpp"
#include "ga.hpp"

namespace coyote_ga {

static std::size_t round_up(std::size_t value, std::size_t alignment) {
    return ((value + alignment - 1) / alignment) * alignment;
}

KernelConfig make_kernel_config(
    const ProblemInstance &problem,
    const CoyoteAppConfig &config,
    uint32_t vfpga_seed,
    uint32_t num_ind
) {
    KernelConfig kc;
    kc.num_individuals = num_ind;
    kc.num_cities = problem.dimension - 1;
    kc.vehicle_capacity = problem.capacity;
    kc.two_opt_k = config.two_opt_k;
    kc.two_opt_enable_precheck = config.two_opt_enable_precheck;
    kc.seed = vfpga_seed;
    kc.crossover_prob = config.crossover_prob;
    kc.mutation_prob = config.mutation_prob;
    return kc;
}

std::uint8_t *allocate_buffer(coyote::cThread &coyote_thread, std::size_t bytes) {
    const std::size_t allocation_bytes = round_up(bytes, coyote::HUGE_PAGE_SIZE);
    return reinterpret_cast<std::uint8_t *>(coyote_thread.getMem({coyote::CoyoteAllocType::HPF, allocation_bytes}));
}

void program_kernel_registers(coyote::cThread &thread, const KernelConfig &config) {
    thread.setCSR(config.num_individuals, CSR_NUM_INDIVIDUALS);
    thread.setCSR(config.num_cities, CSR_NUM_CITIES);
    thread.setCSR(config.vehicle_capacity, CSR_VEHICLE_CAPACITY);
    thread.setCSR(config.two_opt_k, CSR_TWO_OPT_K);
    thread.setCSR(config.two_opt_enable_precheck ? 1 : 0, CSR_TWO_OPT_ENABLE_PRECHECK);
    thread.setCSR(config.seed, CSR_SEED);
    thread.setCSR(config.crossover_prob, CSR_CROSSOVER_PROB);
    thread.setCSR(config.mutation_prob, CSR_MUTATION_PROB);
}

bool validate_kernel_registers(coyote::cThread &thread, unsigned int vfid, const KernelConfig &config) {
    struct RegisterCheck {
        const char *name;
        uint32_t csr_idx;
        uint64_t expected;
    };

    const std::array<RegisterCheck, 8> checks = {{
        {"num_individuals",         CSR_NUM_INDIVIDUALS,         config.num_individuals},
        {"num_cities",              CSR_NUM_CITIES,              config.num_cities},
        {"vehicle_capacity",        CSR_VEHICLE_CAPACITY,        config.vehicle_capacity},
        {"two_opt_k",               CSR_TWO_OPT_K,               static_cast<uint64_t>(config.two_opt_k)},
        {"two_opt_enable_precheck", CSR_TWO_OPT_ENABLE_PRECHECK, static_cast<uint64_t>(config.two_opt_enable_precheck ? 1 : 0)},
        {"seed",                    CSR_SEED,                    config.seed},
        {"crossover_prob",          CSR_CROSSOVER_PROB,          static_cast<uint64_t>(config.crossover_prob)},
        {"mutation_prob",           CSR_MUTATION_PROB,           static_cast<uint64_t>(config.mutation_prob)}
    }};

    for (const auto &chk : checks) {
        uint64_t val = thread.getCSR(chk.csr_idx);
        if (val != chk.expected) {
            std::cerr << "Error: vFPGA " << vfid << " register '" << chk.name
                      << "' (CSR index 0x" << std::hex << chk.csr_idx << std::dec << ") mismatch: "
                      << "expected " << chk.expected << ", got " << val << std::endl;
            return false;
        }
    }
    return true;
}

void program_and_validate_kernel(coyote::cThread &thread, unsigned int vfid, const KernelConfig &config) {
    program_kernel_registers(thread, config);
    if (!validate_kernel_registers(thread, vfid, config)) {
        throw std::runtime_error("Failed to program and validate vFPGA " + std::to_string(vfid) + " kernel registers.");
    }
}

void initialize_node_cache(coyote::cThread &thread, unsigned int vfid, const ProblemInstance &problem) {
    const std::vector<uint8_t> cache_bytes = encode_node_cache(problem);
    std::uint8_t *cache_mem = allocate_buffer(thread, cache_bytes.size());
    if (!cache_mem) {
        throw std::runtime_error("Could not allocate Coyote hugepage buffer for cache on vFPGA " + std::to_string(vfid));
    }
    std::memcpy(cache_mem, cache_bytes.data(), cache_bytes.size());

    coyote::localSg cache_sg = {
        .addr = cache_mem,
        .len = static_cast<uint32_t>(cache_bytes.size()),
        .stream = true,
        .dest = 0
    };

    thread.clearCompleted();
    thread.setCSR(problem.dimension - 1, CSR_NUM_CITIES);
    thread.setCSR(1, CSR_INIT_CITY_CACHE);
    thread.setCSR(CSR_CONTROL_START, CSR_CONTROL);

    thread.invoke(coyote::CoyoteOper::LOCAL_READ, cache_sg);
    while (thread.checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 1) {
        std::this_thread::yield();
    }
    thread.setCSR(0, CSR_INIT_CITY_CACHE);
    thread.clearCompleted();
}

void execute_dual_stream_transfer(
    coyote::cThread &thread,
    const uint8_t *src_0,
    const uint8_t *src_1,
    uint8_t *dst_0,
    uint8_t *dst_1,
    uint32_t len,
    uint32_t seed,
    bool set_seed
) {
    thread.clearCompleted();
    if (set_seed) {
        thread.setCSR(seed, CSR_SEED);
    }
    thread.setCSR(CSR_CONTROL_START, CSR_CONTROL);

    coyote::localSg src_sg_0 = { .addr = const_cast<uint8_t *>(src_0), .len = len, .stream = true, .dest = 0 };
    coyote::localSg src_sg_1 = { .addr = const_cast<uint8_t *>(src_1), .len = len, .stream = true, .dest = 1 };
    coyote::localSg dst_sg_0 = { .addr = dst_0, .len = len, .stream = true, .dest = 0 };
    coyote::localSg dst_sg_1 = { .addr = dst_1, .len = len, .stream = true, .dest = 1 };

    thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg_0, dst_sg_0);
    thread.invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg_1, dst_sg_1);

    while (thread.checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != 2) {
        std::this_thread::yield();
    }
}

bool run_smoke_test(unsigned int vfid, const ProblemInstance &problem, const CoyoteAppConfig &config) {
    HEADER("SMOKE TEST (1 GENERATION ON vFPGA " + std::to_string(vfid) + ")");
    coyote::cThread coyote_thread(vfid, getpid());

    const std::size_t pop_size = config.ga_params.pop_size;
    const std::size_t num_ind_per_stream = pop_size / 2;
    const int beats_per_individual = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_individual = beats_per_individual * AXI_BYTES;
    const std::size_t pop_bytes = pop_size * bytes_per_individual;
    const std::size_t half_pop_bytes = num_ind_per_stream * bytes_per_individual;

    std::uint8_t *src_mem_0 = allocate_buffer(coyote_thread, half_pop_bytes);
    std::uint8_t *src_mem_1 = allocate_buffer(coyote_thread, half_pop_bytes);
    std::uint8_t *dst_mem_0 = allocate_buffer(coyote_thread, half_pop_bytes);
    std::uint8_t *dst_mem_1 = allocate_buffer(coyote_thread, half_pop_bytes);

    if (!src_mem_0 || !src_mem_1 || !dst_mem_0 || !dst_mem_1) {
        throw std::runtime_error("Could not allocate Coyote hugepage buffers for vFPGA " + std::to_string(vfid));
    }

    KernelConfig kcfg = make_kernel_config(problem, config, config.ga_params.seed, static_cast<uint32_t>(num_ind_per_stream));
    program_and_validate_kernel(coyote_thread, vfid, kcfg);
    std::cout << "Programmed and validated all kernel registers on vFPGA " << vfid << "." << std::endl;

    std::cout << "Initializing node cache on vFPGA " << vfid << " beforehand via stream 0..." << std::endl;
    initialize_node_cache(coyote_thread, vfid, problem);
    std::cout << "Node cache successfully initialized on vFPGA " << vfid << "." << std::endl;

    std::cout << "Generating initial population for smoke test on vFPGA " << vfid << "..." << std::endl;
    const std::vector<Individual> init_pop_0 = build_initial_population(problem, num_ind_per_stream, config.ga_params.seed);
    const std::vector<Individual> init_pop_1 = build_initial_population(problem, num_ind_per_stream, config.ga_params.seed ^ 0xBEEF);

    const std::vector<std::uint8_t> enc_0 = encode_population_fixed(problem, init_pop_0);
    const std::vector<std::uint8_t> enc_1 = encode_population_fixed(problem, init_pop_1);

    std::memcpy(src_mem_0, enc_0.data(), half_pop_bytes);
    std::memcpy(src_mem_1, enc_1.data(), half_pop_bytes);
    std::memset(dst_mem_0, 0, half_pop_bytes);
    std::memset(dst_mem_1, 0, half_pop_bytes);

    std::cout << "Invoking vFPGA " << vfid << " for 1 generation..." << std::endl;
    auto create_new_generation = [&]() {
        execute_dual_stream_transfer(
            coyote_thread,
            src_mem_0, src_mem_1,
            dst_mem_0, dst_mem_1,
            static_cast<uint32_t>(half_pop_bytes),
            0,
            false
        );
    };

    coyote::cBench bench(1, 0);
    bench.execute(create_new_generation, [](){});
    double throughput = ((double) pop_bytes) / (1024.0 * 1024.0 * 1e-9 * bench.getAvg());
    std::cout << "Average throughput: " << std::setw(8) << throughput << " MB/s; " << std::endl;

    std::cout << "Decoding output individuals and verifying fitness..." << std::endl;
    const std::vector<Individual> children_0 = decode_population_fixed(problem, dst_mem_0, num_ind_per_stream);
    const std::vector<Individual> children_1 = decode_population_fixed(problem, dst_mem_1, num_ind_per_stream);

    std::vector<Individual> children;
    children.reserve(pop_size);
    children.insert(children.end(), children_0.begin(), children_0.end());
    children.insert(children.end(), children_1.begin(), children_1.end());

    int errors = 0;
    for (std::size_t i = 0; i < pop_size; ++i) {
        if (!validate_solution(problem, children[i], false)) {
            std::cerr << "Validation failed for individual " << i << std::endl;
            errors++;
        }
        uint32_t exp_fit = compute_fitness(problem, children[i]);
        if (children[i].fitness != exp_fit) {
            std::cerr << "Mismatch in individual " << i << ": got "
                      << children[i].fitness << ", expected " << exp_fit << std::endl;
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "SMOKE TEST PASSED on vFPGA " << vfid << ": Processed " << pop_size << " individuals successfully on FPGA." << std::endl;
        return true;
    } else {
        std::cerr << "SMOKE TEST FAILED on vFPGA " << vfid << " with " << errors << " errors." << std::endl;
        return false;
    }
}

bool run_smoke_tests_all(const ProblemInstance &problem, const CoyoteAppConfig &config) {
    HEADER("SMOKE TEST (1 GENERATION ON EACH vFPGA)");
    bool all_passed = true;
    for (unsigned int vfid = 0; vfid < kNumVfpgas; ++vfid) {
        if (!run_smoke_test(vfid, problem, config)) {
            all_passed = false;
        }
    }
    if (all_passed) {
        std::cout << "ALL SMOKE TESTS PASSED (" << kNumVfpgas << " vFPGA(s))." << std::endl;
    } else {
        std::cerr << "SMOKE TEST FAILED on one or more vFPGAs." << std::endl;
    }
    return all_passed;
}

GASummary run_pipelined_ga(const ProblemInstance &problem, CoyoteAppConfig &config) {
    std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;
    coyote_threads.reserve(kNumVfpgas);
    for (unsigned int vfid = 0; vfid < kNumVfpgas; ++vfid) {
        coyote_threads.emplace_back(std::make_unique<coyote::cThread>(vfid, getpid()));
    }

    const int beats_per_individual = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_individual = beats_per_individual * AXI_BYTES;
    const std::size_t pop_bytes = config.ga_params.pop_size * bytes_per_individual;

    std::size_t batch_ind_per_stream = (config.ga_params.pop_size / 2) / kNumVfpgas;
    if (batch_ind_per_stream == 0) {
        batch_ind_per_stream = 1;
    }
    config.ga_params.num_ind_per_stream = batch_ind_per_stream;
    config.ga_params.num_vfpgas = kNumVfpgas;

    const std::size_t batch_bytes = batch_ind_per_stream * bytes_per_individual;

    std::cout << "Micro-batch size: " << batch_ind_per_stream << " individuals/stream ("
              << (2 * batch_ind_per_stream) << " offspring per batch, "
              << batch_bytes << " bytes per stream)" << std::endl;

    for (unsigned int vfid = 0; vfid < kNumVfpgas; ++vfid) {
        const uint32_t vfpga_seed = config.ga_params.seed ^ (0x9E3779B9u * (vfid + 1));
        KernelConfig kcfg = make_kernel_config(problem, config, vfpga_seed, static_cast<uint32_t>(batch_ind_per_stream));
        program_and_validate_kernel(*coyote_threads[vfid], vfid, kcfg);
    }
    std::cout << "Successfully programmed and validated kernel configuration registers on all "
              << kNumVfpgas << " vFPGAs." << std::endl;

    std::cout << "Initializing node cache on " << kNumVfpgas << " vFPGA(s) beforehand via stream 0..." << std::endl;
    for (unsigned int vfid = 0; vfid < kNumVfpgas; ++vfid) {
        initialize_node_cache(*coyote_threads[vfid], vfid, problem);
    }
    std::cout << "Node cache successfully initialized on all " << kNumVfpgas << " vFPGA(s)." << std::endl;

    constexpr std::size_t slots_per_vfpga = 2;
    std::vector<BatchBufferSlot> buffer_slots;
    buffer_slots.reserve(kNumVfpgas * slots_per_vfpga);

    for (unsigned int vfid = 0; vfid < kNumVfpgas; ++vfid) {
        for (std::size_t s = 0; s < slots_per_vfpga; ++s) {
            std::uint8_t *src_0 = allocate_buffer(*coyote_threads[vfid], batch_bytes);
            std::uint8_t *src_1 = allocate_buffer(*coyote_threads[vfid], batch_bytes);
            std::uint8_t *dst_0 = allocate_buffer(*coyote_threads[vfid], batch_bytes);
            std::uint8_t *dst_1 = allocate_buffer(*coyote_threads[vfid], batch_bytes);

            if (!src_0 || !src_1 || !dst_0 || !dst_1) {
                throw std::runtime_error("Could not allocate Coyote hugepage buffers for vFPGA " + std::to_string(vfid));
            }

            BatchBufferSlot slot;
            slot.slot_id = static_cast<int>(vfid * slots_per_vfpga + s);
            slot.vfid = static_cast<int>(vfid);
            slot.num_ind_per_stream = batch_ind_per_stream;
            slot.src_buf_0 = src_0;
            slot.src_buf_1 = src_1;
            slot.dst_buf_0 = dst_0;
            slot.dst_buf_1 = dst_1;
            buffer_slots.push_back(slot);
        }
    }
    config.ga_params.buffer_slots = std::move(buffer_slots);

    std::unique_ptr<std::uint8_t[], void(*)(void*)> pop_mem(nullptr, std::free);
    void *ptr = nullptr;
    if (posix_memalign(&ptr, AXI_BYTES, pop_bytes) != 0 || !ptr) {
        throw std::bad_alloc();
    }
    pop_mem.reset(reinterpret_cast<std::uint8_t *>(ptr));
    config.ga_params.buffer_pop = pop_mem.get();

    auto execute_vfpga_batch = [&](int vfid, const BatchJob &job) {
        execute_dual_stream_transfer(
            *coyote_threads[vfid],
            job.src_buf_0, job.src_buf_1,
            job.dst_buf_0, job.dst_buf_1,
            static_cast<uint32_t>(batch_bytes),
            job.batch_seed,
            true /* set_seed */
        );
    };

    HEADER("RUNNING ASYNC PIPELINED GA ON " + std::to_string(kNumVfpgas) + " vFPGAs");
    return run_ga_pipelined(problem, config.ga_params, execute_vfpga_batch);
}

} // namespace coyote_ga
