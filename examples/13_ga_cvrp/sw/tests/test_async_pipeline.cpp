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

/**
 * Standalone unit and integration tests for the asynchronous multi-vFPGA pipeline.
 * Tests SafeQueue and run_ga_pipelined with simulated worker latency.
 * No hardware or Coyote driver required.
 *
 * Build & Run:
 *   g++ -std=c++17 -I . -pthread test_async_pipeline.cpp ga.cpp ga_streaming.cpp problem_parser.cpp -o test_async_pipeline && ./test_async_pipeline
 */

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <memory>
#include <thread>
#include <vector>

#include "ga.hpp"
#include "ga_streaming.hpp"
#include "safe_queue.hpp"
#include "problem_parser.hpp"

namespace {

void test_safe_queue_basic() {
    std::cout << "Test 1: SafeQueue basic push/pop and shutdown...\n";
    SafeQueue<int> q;
    q.push(10);
    q.push(20);

    auto v1 = q.pop();
    auto v2 = q.pop();

    if (!v1 || *v1 != 10 || !v2 || *v2 != 20) {
        std::cerr << "FAIL: SafeQueue basic push/pop mismatch.\n";
        std::exit(EXIT_FAILURE);
    }

    std::thread consumer([&q]() {
        auto val = q.pop();
        if (val.has_value()) {
            std::cerr << "FAIL: expected nullopt on shutdown.\n";
            std::exit(EXIT_FAILURE);
        }
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    q.shutdown();
    consumer.join();
    std::cout << "PASS [test_safe_queue_basic]\n";
}

void test_safe_queue_multithreaded() {
    std::cout << "Test 2: SafeQueue multi-producer multi-consumer stress test...\n";
    SafeQueue<int> q;
    constexpr int n_items = 1000;
    std::atomic<int> sum_consumed{0};

    std::vector<std::thread> producers;
    for (int p = 0; p < 4; ++p) {
        producers.emplace_back([&q, p]() {
            for (int i = 0; i < n_items; ++i) {
                q.push(1);
            }
        });
    }

    std::vector<std::thread> consumers;
    for (int c = 0; c < 4; ++c) {
        consumers.emplace_back([&q, &sum_consumed]() {
            while (true) {
                auto val = q.pop();
                if (!val) break;
                sum_consumed += *val;
            }
        });
    }

    for (auto &p : producers) p.join();

    while (q.size() > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    q.shutdown();
    for (auto &c : consumers) c.join();

    if (sum_consumed.load() != 4 * n_items) {
        std::cerr << "FAIL: Expected sum " << (4 * n_items) << " but got " << sum_consumed.load() << "\n";
        std::exit(EXIT_FAILURE);
    }
    std::cout << "PASS [test_safe_queue_multithreaded]\n";
}

ProblemInstance create_toy_problem() {
    ProblemInstance p;
    p.name = "toy_problem";
    p.dimension = 6;
    p.capacity = 30;
    p.scaling = 1;
    p.depot = ProblemNode{0, 0, 0, 0};
    p.nodes = {
        ProblemNode{0, 10, 10, 5},
        ProblemNode{1, 10, -10, 10},
        ProblemNode{2, -10, 10, 8},
        ProblemNode{3, -10, -10, 12},
        ProblemNode{4, 0, 15, 6}
    };
    return p;
}

void test_run_ga_pipelined_simulation(std::size_t num_vfpgas) {
    std::cout << "Test: run_ga_pipelined with N=" << num_vfpgas << " simulated vFPGAs...\n";

    ProblemInstance problem = create_toy_problem();
    const std::size_t pop_size = 20;
    const std::size_t n_generations = 10;
    const int beats_per_ind = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_ind = beats_per_ind * AXI_BYTES;
    const std::size_t pop_bytes = pop_size * bytes_per_ind;

    const std::size_t batch_ind_per_stream = 5;
    const std::size_t batch_bytes = batch_ind_per_stream * bytes_per_ind;

    AsyncGAParams params;
    params.pop_size = pop_size;
    params.n_generations = n_generations;
    params.n_best_keep = 10.0;
    params.seed = 0xC0FFEE;
    params.num_vfpgas = num_vfpgas;
    params.num_ind_per_stream = batch_ind_per_stream;

    std::vector<std::uint8_t> pop_mem(pop_bytes);
    params.buffer_pop = pop_mem.data();

    const std::size_t slots_per_vfpga = 2;
    std::vector<std::vector<std::uint8_t>> storage_src0;
    std::vector<std::vector<std::uint8_t>> storage_src1;
    std::vector<std::vector<std::uint8_t>> storage_dst0;
    std::vector<std::vector<std::uint8_t>> storage_dst1;

    for (std::size_t v = 0; v < num_vfpgas; ++v) {
        for (std::size_t s = 0; s < slots_per_vfpga; ++s) {
            storage_src0.emplace_back(batch_bytes, 0);
            storage_src1.emplace_back(batch_bytes, 0);
            storage_dst0.emplace_back(batch_bytes, 0);
            storage_dst1.emplace_back(batch_bytes, 0);

            BatchBufferSlot slot;
            slot.slot_id = static_cast<int>(v * slots_per_vfpga + s);
            slot.vfid = static_cast<int>(v);
            slot.num_ind_per_stream = batch_ind_per_stream;
            slot.src_buf_0 = storage_src0.back().data();
            slot.src_buf_1 = storage_src1.back().data();
            slot.dst_buf_0 = storage_dst0.back().data();
            slot.dst_buf_1 = storage_dst1.back().data();

            params.buffer_slots.push_back(slot);
        }
    }

    auto mock_vfpga_executor = [&](int vfid, const BatchJob &job) {
        std::this_thread::sleep_for(std::chrono::microseconds(100));

        if (job.parents1.size() != job.num_ind_per_stream || job.parents2.size() != job.num_ind_per_stream) {
            std::cerr << "FAIL: BatchJob parents vectors not populated on job.\n";
            std::exit(EXIT_FAILURE);
        }

        std::memcpy(job.dst_buf_0, job.src_buf_0, job.num_ind_per_stream * bytes_per_ind);
        std::memcpy(job.dst_buf_1, job.src_buf_1, job.num_ind_per_stream * bytes_per_ind);
    };

    GASummary summary = run_ga_pipelined(problem, params, mock_vfpga_executor);

    // Validate that the best individual returned is a valid CVRP solution
    validate_solution(problem, summary.best_individual);
    if (!summary.best_individual.validate(problem)) {
        std::cerr << "FAIL: summary.best_individual failed validation\n";
        std::exit(EXIT_FAILURE);
    }

    // Validate the entire final population
    const std::vector<Individual> final_pop = decode_population_fixed(problem, params.buffer_pop, pop_size);
    validate_population(problem, final_pop);

    if (summary.best_fitness == 0.0 || summary.best_fitness > 100000.0) {
        std::cerr << "FAIL: Invalid best fitness: " << summary.best_fitness << "\n";
        std::exit(EXIT_FAILURE);
    }
    if (summary.exact_best_fitness <= 0.0) {
        std::cerr << "FAIL: exact_best_fitness must be positive: " << summary.exact_best_fitness << "\n";
        std::exit(EXIT_FAILURE);
    }
    if (summary.best_fitness_history.size() != n_generations + 1) {
        std::cerr << "FAIL: best_fitness_history size " << summary.best_fitness_history.size()
                  << " != expected " << (n_generations + 1) << "\n";
        std::exit(EXIT_FAILURE);
    }
    for (std::size_t i = 0; i < summary.best_fitness_history.size(); ++i) {
        if (summary.best_fitness_history[i].generation != i) {
            std::cerr << "FAIL: Generation index mismatch at " << i << ": got "
                      << summary.best_fitness_history[i].generation << "\n";
            std::exit(EXIT_FAILURE);
        }
        if (summary.best_fitness_history[i].timestamp_ms < 0.0) {
            std::cerr << "FAIL: Negative timestamp at gen " << i << "\n";
            std::exit(EXIT_FAILURE);
        }
    }
    if (summary.timings.total_time_ms <= 0.0) {
        std::cerr << "FAIL: Total time must be positive.\n";
        std::exit(EXIT_FAILURE);
    }
    if (summary.timings.cpu.active_time_ms <= 0.0) {
        std::cerr << "FAIL: CPU active time must be positive: " << summary.timings.cpu.active_time_ms << "\n";
        std::exit(EXIT_FAILURE);
    }
    if (summary.timings.workers.size() != num_vfpgas) {
        std::cerr << "FAIL: Worker count mismatch: got " << summary.timings.workers.size()
                  << ", expected " << num_vfpgas << "\n";
        std::exit(EXIT_FAILURE);
    }
    for (const auto &w : summary.timings.workers) {
        if (w.batches_processed == 0) {
            std::cerr << "FAIL: Worker " << w.vfid << " processed 0 batches\n";
            std::exit(EXIT_FAILURE);
        }
        if (w.active_time_ms <= 0.0) {
            std::cerr << "FAIL: Worker " << w.vfid << " active time must be positive\n";
            std::exit(EXIT_FAILURE);
        }
    }

    std::string test_json_path = "/tmp/test_doe_output.json";
    summary.save_json(test_json_path, problem);
    std::ifstream jf(test_json_path);
    if (!jf.is_open()) {
        std::cerr << "FAIL: Failed to open exported test JSON file\n";
        std::exit(EXIT_FAILURE);
    }
    jf.close();
    std::remove(test_json_path.c_str());

    std::cout << "PASS [run_ga_pipelined simulation N=" << num_vfpgas
              << ", HW Fitness=" << summary.best_fitness
              << ", Exact Fitness=" << summary.exact_best_fitness
              << ", History Points=" << summary.best_fitness_history.size()
              << ", Wall Time=" << summary.timings.total_time_ms << " ms]\n";
}

void test_safe_queue_priority_and_pop_expected() {
    std::cout << "Test 3: SafeQueue priority order & pop_expected...\n";
    SafeQueue<BatchJob> q;

    BatchJob j2; j2.batch_id = 2;
    BatchJob j0; j0.batch_id = 0;
    BatchJob j1; j1.batch_id = 1;

    q.push(j2);
    q.push(j0);
    q.push(j1);

    auto p0 = q.pop();
    auto p1 = q.pop();
    auto p2 = q.pop();

    if (!p0 || p0->batch_id != 0 || !p1 || p1->batch_id != 1 || !p2 || p2->batch_id != 2) {
        std::cerr << "FAIL: SafeQueue min-heap ordering mismatch.\n";
        std::exit(EXIT_FAILURE);
    }

    std::thread producer([&q]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        BatchJob j_high; j_high.batch_id = 10;
        q.push(j_high);

        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        BatchJob j_target; j_target.batch_id = 5;
        q.push(j_target);
    });

    auto res = q.pop_expected(5);
    producer.join();

    if (!res || res->batch_id != 5) {
        std::cerr << "FAIL: pop_expected failed to wait for target batch.\n";
        std::exit(EXIT_FAILURE);
    }

    auto res2 = q.pop();
    if (!res2 || res2->batch_id != 10) {
        std::cerr << "FAIL: Remaining batch in priority queue mismatch.\n";
        std::exit(EXIT_FAILURE);
    }

    std::cout << "PASS [test_safe_queue_priority_and_pop_expected]\n";
}

void test_run_ga_pipelined_reproducibility() {
    std::cout << "Test 4: run_ga_pipelined reproducibility with N=4 and jitter...\n";
    ProblemInstance problem = create_toy_problem();
    const std::size_t pop_size = 20;
    const std::size_t n_generations = 10;
    const int beats_per_ind = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_ind = beats_per_ind * AXI_BYTES;
    const std::size_t pop_bytes = pop_size * bytes_per_ind;
    const std::size_t batch_ind_per_stream = 5;
    const std::size_t batch_bytes = batch_ind_per_stream * bytes_per_ind;

    auto run_simulation = [&](uint32_t run_seed) -> GASummary {
        AsyncGAParams params;
        params.pop_size = pop_size;
        params.n_generations = n_generations;
        params.n_best_keep = 10.0;
        params.seed = run_seed;
        params.num_vfpgas = 4;
        params.num_ind_per_stream = batch_ind_per_stream;

        std::vector<std::uint8_t> pop_mem(pop_bytes);
        params.buffer_pop = pop_mem.data();

        const std::size_t slots_per_vfpga = 2;
        std::vector<std::vector<std::uint8_t>> storage_src0;
        std::vector<std::vector<std::uint8_t>> storage_src1;
        std::vector<std::vector<std::uint8_t>> storage_dst0;
        std::vector<std::vector<std::uint8_t>> storage_dst1;

        for (std::size_t v = 0; v < 4; ++v) {
            for (std::size_t s = 0; s < slots_per_vfpga; ++s) {
                storage_src0.emplace_back(batch_bytes, 0);
                storage_src1.emplace_back(batch_bytes, 0);
                storage_dst0.emplace_back(batch_bytes, 0);
                storage_dst1.emplace_back(batch_bytes, 0);

                BatchBufferSlot slot;
                slot.slot_id = static_cast<int>(v * slots_per_vfpga + s);
                slot.vfid = static_cast<int>(v);
                slot.num_ind_per_stream = batch_ind_per_stream;
                slot.src_buf_0 = storage_src0.back().data();
                slot.src_buf_1 = storage_src1.back().data();
                slot.dst_buf_0 = storage_dst0.back().data();
                slot.dst_buf_1 = storage_dst1.back().data();
                params.buffer_slots.push_back(slot);
            }
        }

        auto mock_vfpga_executor = [&](int vfid, const BatchJob &job) {
            // Introduce intentional randomized jitter per vFPGA to simulate out-of-order completion
            int jitter_us = 50 + (rand() % 150);
            std::this_thread::sleep_for(std::chrono::microseconds(jitter_us));

            if (job.parents1.size() != job.num_ind_per_stream || job.parents2.size() != job.num_ind_per_stream) {
                std::cerr << "FAIL: BatchJob parents vectors not populated on job in reproducibility test.\n";
                std::exit(EXIT_FAILURE);
            }

            std::memcpy(job.dst_buf_0, job.src_buf_0, job.num_ind_per_stream * bytes_per_ind);
            std::memcpy(job.dst_buf_1, job.src_buf_1, job.num_ind_per_stream * bytes_per_ind);
        };

        return run_ga_pipelined(problem, params, mock_vfpga_executor);
    };

    GASummary r1 = run_simulation(0x1234ABCD);
    GASummary r2 = run_simulation(0x1234ABCD);

    // Validate solutions from both runs
    validate_solution(problem, r1.best_individual);
    validate_solution(problem, r2.best_individual);

    if (r1.best_fitness != r2.best_fitness) {
        std::cerr << "FAIL: Reproducibility check failed! Fitness 1: " << r1.best_fitness
                  << ", Fitness 2: " << r2.best_fitness << "\n";
        std::exit(EXIT_FAILURE);
    }

    if (r1.best_individual != r2.best_individual) {
        std::cerr << "FAIL: Reproducibility check failed! Best individuals differ.\n";
        std::exit(EXIT_FAILURE);
    }

    std::cout << "PASS [test_run_ga_pipelined_reproducibility: bit-exact match across jittered runs]\n";
}

} // namespace

int main() {
    std::cout << "========================================\n";
    std::cout << "Running Async Multi-vFPGA Pipeline Tests\n";
    std::cout << "========================================\n";

    test_safe_queue_basic();
    test_safe_queue_multithreaded();
    test_safe_queue_priority_and_pop_expected();
    test_run_ga_pipelined_simulation(1);
    test_run_ga_pipelined_simulation(2);
    test_run_ga_pipelined_simulation(4);
    test_run_ga_pipelined_reproducibility();

    std::cout << "========================================\n";
    std::cout << "Result: All Async Pipeline Tests Passed!\n";
    std::cout << "========================================\n";
    return EXIT_SUCCESS;
}
