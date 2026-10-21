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

#include "ga_engine.hpp"
#include "ga_operators.hpp"
#include "ga_streaming.hpp"
#include "safe_queue.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <thread>

void GASummary::print() const {
    print(std::cout);
}

void GASummary::print(std::ostream &os) const {
    auto old_flags = os.flags();
    auto old_prec = os.precision();

    os << "\n============================== GA EXECUTION SUMMARY ==============================\n";
    os << "--- Solution Overview ------------------------------------------------------------\n";
    os << "  Generations:          " << n_generations << "\n";
    os << "  Population Size:      " << pop_size << "\n";
    os << std::fixed << std::setprecision(3);
    os << "  Initial Best Fitness: " << initial_best_fitness << "\n";
    os << "  HW Best Fitness:      " << best_fitness << "\n";
    os << "  Exact Best Fitness:   " << exact_best_fitness << "\n";
    os << "  Best Found at Gen:    " << gen_best_found << "\n";
    if (initial_best_fitness > 0.0) {
        double imp = (initial_best_fitness - exact_best_fitness) / initial_best_fitness * 100.0;
        os << "  Improvement:          " << imp << " %\n";
    }
    os << "----------------------------------------------------------------------------------\n";
    os << "\n--- Execution Timing & Hardware Utilization --------------------------------------\n";
    os << "  Total Wall Time:      " << timings.total_time_ms << " ms ("
       << (timings.total_time_ms / 1000.0) << " s)\n";
    if (timings.total_time_ms > 0.0) {
        os << "  Throughput:           " << static_cast<uint64_t>(throughput_evals_sec()) << " evals/sec ("
           << std::setprecision(1) << (static_cast<double>(n_generations) / (timings.total_time_ms / 1000.0)) << " gen/sec)\n";
    }
    os << "  --------------------------------------------------------------------------------\n";
    os << "  " << std::left << std::setw(22) << "Component"
       << std::right << std::setw(14) << "Active (ms)"
       << std::right << std::setw(14) << "Idle (ms)"
       << std::right << std::setw(14) << "Total (ms)"
       << std::right << std::setw(14) << "Util (%)" << "\n";
    os << "  --------------------------------------------------------------------------------\n";
    os << std::fixed << std::setprecision(2);
    os << "  " << std::left << std::setw(22) << "CPU Manager"
       << std::right << std::setw(14) << timings.cpu.active_time_ms
       << std::right << std::setw(14) << timings.cpu.idle_time_ms
       << std::right << std::setw(14) << timings.cpu.total_time_ms()
       << std::right << std::setw(13) << timings.cpu.utilization_pct() << " %\n";
    os << "    - Initialization:    " << timings.cpu.init_time_ms << " ms\n";
    os << "    - Parent Selection:  " << timings.cpu.parent_selection_ms << " ms\n";
    os << "    - Population Update: " << timings.cpu.population_update_ms << " ms\n";

    for (const auto &w : timings.workers) {
        std::string label = "vFPGA " + std::to_string(w.vfid) + " Worker";
        os << "  " << std::left << std::setw(22) << label
           << std::right << std::setw(14) << w.active_time_ms
           << std::right << std::setw(14) << w.idle_time_ms
           << std::right << std::setw(14) << w.total_time_ms()
           << std::right << std::setw(13) << w.utilization_pct() << " %"
           << " (" << w.batches_processed << " batches)\n";
    }
    os << "==================================================================================\n";

    os.flags(old_flags);
    os.precision(old_prec);
}

void GASummary::save_json(const std::string &path, const ProblemInstance &problem) const {
    std::ofstream ofs(path);
    if (!ofs.is_open()) {
        std::cerr << "Error: could not open output file: " << path << std::endl;
        return;
    }

    ofs << "{\n";
    ofs << "  \"problem\": {\n";
    ofs << "    \"name\": \"" << problem.name << "\",\n";
    ofs << "    \"dimension\": " << problem.dimension << ",\n";
    ofs << "    \"capacity\": " << problem.capacity << ",\n";
    ofs << "    \"scaling\": " << problem.scaling << "\n";
    ofs << "  },\n";

    ofs << "  \"ga_parameters\": {\n";
    ofs << "    \"n_generations\": " << n_generations << ",\n";
    ofs << "    \"pop_size\": " << pop_size << "\n";
    ofs << "  },\n";

    ofs << "  \"solution\": {\n";
    ofs << std::fixed << std::setprecision(6);
    ofs << "    \"initial_best_fitness\": " << initial_best_fitness << ",\n";
    ofs << "    \"hw_best_fitness\": " << best_fitness << ",\n";
    ofs << "    \"exact_best_fitness\": " << exact_best_fitness << ",\n";
    ofs << "    \"gen_best_found\": " << gen_best_found << ",\n";
    double imp = initial_best_fitness > 0.0 ? ((initial_best_fitness - exact_best_fitness) / initial_best_fitness * 100.0) : 0.0;
    ofs << "    \"improvement_pct\": " << imp << "\n";
    ofs << "  },\n";

    ofs << "  \"timings\": {\n";
    ofs << "    \"total_wall_time_ms\": " << timings.total_time_ms << ",\n";
    ofs << "    \"throughput_evals_sec\": " << throughput_evals_sec() << ",\n";
    ofs << "    \"cpu\": {\n";
    ofs << "      \"active_time_ms\": " << timings.cpu.active_time_ms << ",\n";
    ofs << "      \"idle_time_ms\": " << timings.cpu.idle_time_ms << ",\n";
    ofs << "      \"utilization_pct\": " << timings.cpu.utilization_pct() << ",\n";
    ofs << "      \"init_time_ms\": " << timings.cpu.init_time_ms << ",\n";
    ofs << "      \"parent_selection_ms\": " << timings.cpu.parent_selection_ms << ",\n";
    ofs << "      \"population_update_ms\": " << timings.cpu.population_update_ms << "\n";
    ofs << "    },\n";

    ofs << "    \"workers\": [\n";
    for (std::size_t i = 0; i < timings.workers.size(); ++i) {
        const auto &w = timings.workers[i];
        ofs << "      {\n";
        ofs << "        \"vfid\": " << w.vfid << ",\n";
        ofs << "        \"active_time_ms\": " << w.active_time_ms << ",\n";
        ofs << "        \"idle_time_ms\": " << w.idle_time_ms << ",\n";
        ofs << "        \"utilization_pct\": " << w.utilization_pct() << ",\n";
        ofs << "        \"batches_processed\": " << w.batches_processed << "\n";
        ofs << "      }" << (i + 1 < timings.workers.size() ? "," : "") << "\n";
    }
    ofs << "    ]\n";
    ofs << "  },\n";

    ofs << "  \"best_fitness_history\": [\n";
    for (std::size_t i = 0; i < best_fitness_history.size(); ++i) {
        const auto &rec = best_fitness_history[i];
        ofs << "    {\"generation\": " << rec.generation
            << ", \"timestamp_ms\": " << rec.timestamp_ms
            << ", \"best_fitness\": " << rec.best_fitness << "}"
            << (i + 1 < best_fitness_history.size() ? "," : "") << "\n";
    }
    ofs << "  ]\n";
    ofs << "}\n";
}

std::ostream& operator<<(std::ostream &os, const GASummary &summary) {
    summary.print(os);
    return os;
}

Individual evaluate_population_exact_best(
    const ProblemInstance &problem,
    const std::vector<EncodedIndividual> &population,
    double &out_best_exact_fitness
) {
    double best_exact = std::numeric_limits<double>::infinity();
    Individual best_ind;

    for (const auto &enc_ind : population) {
        if (enc_ind.bytes != nullptr) {
            Individual ind = decode_individual_fixed(problem, enc_ind.bytes);
            validate_solution(problem, ind, true);
            double exact_fit = compute_exact_fitness(problem, ind);
            if (exact_fit < best_exact) {
                best_exact = exact_fit;
                best_ind = std::move(ind);
            }
        }
    }

    out_best_exact_fitness = best_exact;
    return best_ind;
}

bool validate_population(
    const ProblemInstance &problem,
    const std::vector<EncodedIndividual> &population,
    bool throw_on_error
) {
    for (std::size_t i = 0; i < population.size(); ++i) {
        if (population[i].bytes != nullptr) {
            Individual ind = decode_individual_fixed(problem, population[i].bytes);
            try {
                if (!validate_solution(problem, ind, throw_on_error)) {
                    return false;
                }
            } catch (const std::exception &e) {
                if (throw_on_error) {
                    throw std::runtime_error("Population validation failed at individual " +
                                             std::to_string(i) + ": " + e.what());
                }
                return false;
            }
        }
    }
    return true;
}

GASummary run_ga(const ProblemInstance& problem, GAParams& params, std::function<void()> create_new_generation) {
    auto wall_start = std::chrono::steady_clock::now();
    GASummary summary;
    summary.n_generations = params.n_generations;
    summary.pop_size = params.pop_size;
    summary.best_fitness_history.reserve(params.n_generations + 1);

    auto init_start = std::chrono::steady_clock::now();
    std::mt19937 new_seed(params.seed);

    const std::size_t pop_size = params.pop_size;
    const std::size_t half_pop = pop_size / 2;
    const int beats_per_ind = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_ind = beats_per_ind * AXI_BYTES;
    const std::size_t half_bytes = half_pop * bytes_per_ind;

    std::vector<Individual> initial_population = build_initial_population(problem, pop_size, new_seed());
    const std::vector<std::uint8_t> encoded_population = encode_population_fixed(problem, initial_population);

    std::vector<EncodedIndividual> vec1 = std::vector<EncodedIndividual>(pop_size);
    std::reference_wrapper<std::vector<EncodedIndividual>> population = vec1;

    std::vector<EncodedIndividual> vec2 = std::vector<EncodedIndividual>(pop_size);
    std::reference_wrapper<std::vector<EncodedIndividual>> next_generation = vec2;

    std::vector<EncodedIndividual> vec3 = std::vector<EncodedIndividual>(pop_size);
    std::reference_wrapper<std::vector<EncodedIndividual>> next_population = vec3;

    std::vector<EncodedIndividual> parents1(half_pop);
    std::vector<EncodedIndividual> parents2(half_pop);

    std::uint8_t *buffer_src_0 = params.buffer_src_0;
    std::uint8_t *buffer_src_1 = params.buffer_src_1;
    std::uint8_t *buffer_dst_0 = params.buffer_dst_0;
    std::uint8_t *buffer_dst_1 = params.buffer_dst_1;
    std::uint8_t *pop_buffer = params.buffer_pop;

    const std::size_t print_interval = std::max<std::size_t>(1, params.n_generations / 10);

    std::memcpy(buffer_src_0, encoded_population.data(), half_bytes);
    std::memcpy(buffer_src_1, encoded_population.data() + half_bytes, half_bytes);
    population_from_buffer(buffer_src_0, half_pop, population, problem.dimension, 0);
    population_from_buffer(buffer_src_1, half_pop, population, problem.dimension, half_pop);
    std::sort(population.get().begin(), population.get().end());
    population_to_buffer(population, pop_buffer, problem.dimension);

    const std::size_t n_keep = std::min(pop_size, static_cast<std::size_t>(std::round(pop_size * (params.n_best_keep / 100.0))));
    auto init_end = std::chrono::steady_clock::now();
    summary.timings.cpu.init_time_ms = std::chrono::duration<double, std::milli>(init_end - init_start).count();

    const double initial_best = static_cast<double>(population.get()[0].fitness) / static_cast<double>(problem.scaling);
    summary.initial_best_fitness = initial_best;
    auto now_init = std::chrono::steady_clock::now();
    double init_elapsed_ms = std::chrono::duration<double, std::milli>(now_init - wall_start).count();
    summary.best_fitness_history.push_back({0, init_elapsed_ms, initial_best});
    double current_best_val = initial_best;
    summary.gen_best_found = 0;

    double fpga_active_ms = 0.0;

    for (std::size_t i = 0; i < params.n_generations; i++) {
        auto t0 = std::chrono::steady_clock::now();
        create_parent_pairs(population, parents1, parents2, new_seed());
        population_to_buffer(parents1, buffer_src_0, problem.dimension);
        population_to_buffer(parents2, buffer_src_1, problem.dimension);
        auto t1 = std::chrono::steady_clock::now();
        
        create_new_generation();
        auto t2 = std::chrono::steady_clock::now();

        population_from_buffer(buffer_dst_0, half_pop, next_generation, problem.dimension, 0);
        population_from_buffer(buffer_dst_1, half_pop, next_generation, problem.dimension, half_pop);
        update_generation_with_parents(next_generation.get(), parents1, parents2);
        update_population(population, next_generation, next_population, n_keep);
        std::swap(population, next_population);
        population_to_buffer(population, pop_buffer, problem.dimension, true);
        auto t3 = std::chrono::steady_clock::now();

        summary.timings.cpu.parent_selection_ms += std::chrono::duration<double, std::milli>(t1 - t0).count();
        fpga_active_ms += std::chrono::duration<double, std::milli>(t2 - t1).count();
        summary.timings.cpu.population_update_ms += std::chrono::duration<double, std::milli>(t3 - t2).count();

        const double current_best = static_cast<double>(population.get()[0].fitness) / static_cast<double>(problem.scaling);
        auto now_gen = std::chrono::steady_clock::now();
        double gen_elapsed_ms = std::chrono::duration<double, std::milli>(now_gen - wall_start).count();
        summary.best_fitness_history.push_back({i + 1, gen_elapsed_ms, current_best});
        if (current_best < current_best_val) {
            current_best_val = current_best;
            summary.gen_best_found = i + 1;
        }

        if (i % print_interval == 0) {
            std::cout << "Iteration " << i << " completed. Best fitness: " << current_best << std::endl;
        }
    }

    auto wall_end = std::chrono::steady_clock::now();
    summary.timings.total_time_ms = std::chrono::duration<double, std::milli>(wall_end - wall_start).count();
    summary.timings.cpu.idle_time_ms = fpga_active_ms;
    summary.timings.cpu.active_time_ms = summary.timings.cpu.init_time_ms +
                                         summary.timings.cpu.parent_selection_ms +
                                         summary.timings.cpu.population_update_ms;

    WorkerTiming w0;
    w0.vfid = 0;
    w0.active_time_ms = fpga_active_ms;
    w0.idle_time_ms = std::max(0.0, summary.timings.total_time_ms - fpga_active_ms);
    w0.batches_processed = params.n_generations;
    summary.timings.workers.push_back(w0);

    validate_population(problem, population.get());
    summary.best_individual = evaluate_population_exact_best(problem, population.get(), summary.exact_best_fitness);
    summary.best_fitness = static_cast<double>(summary.best_individual.fitness) / static_cast<double>(problem.scaling);

    return summary;
}

GASummary run_ga_pipelined(
    const ProblemInstance &problem,
    AsyncGAParams &params,
    VfpgaExecuteFn execute_vfpga_batch
) {
    auto wall_start = std::chrono::steady_clock::now();
    GASummary summary;
    summary.n_generations = params.n_generations;
    summary.pop_size = params.pop_size;
    summary.best_fitness_history.reserve(params.n_generations + 1);

    auto init_start = std::chrono::steady_clock::now();
    std::mt19937 new_seed(params.seed);

    const std::size_t pop_size = params.pop_size;
    const std::size_t num_vfpgas = std::max<std::size_t>(1, params.num_vfpgas);
    const std::size_t batch_ind_per_stream = params.num_ind_per_stream > 0 ? params.num_ind_per_stream : (pop_size / (2 * num_vfpgas));
    const std::size_t offspring_per_batch = 2 * batch_ind_per_stream;

    if (params.buffer_slots.empty()) {
        throw std::runtime_error("run_ga_pipelined: params.buffer_slots is empty. Pre-allocated buffer slots required.");
    }
    if (!params.buffer_pop) {
        throw std::runtime_error("run_ga_pipelined: params.buffer_pop is null. Population scratchpad buffer required.");
    }

    std::vector<Individual> initial_population = build_initial_population(problem, pop_size, new_seed());
    const std::vector<std::uint8_t> encoded_population = encode_population_fixed(problem, initial_population);

    const int beats_per_ind = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_ind = beats_per_ind * AXI_BYTES;
    const std::size_t pop_bytes = pop_size * bytes_per_ind;

    std::memcpy(params.buffer_pop, encoded_population.data(), pop_bytes);

    std::vector<EncodedIndividual> population_vec(pop_size);
    std::vector<EncodedIndividual> next_population_vec(pop_size);
    population_from_buffer(params.buffer_pop, pop_size, population_vec, problem.dimension, 0);
    std::sort(population_vec.begin(), population_vec.end());
    population_to_buffer(population_vec, params.buffer_pop, problem.dimension);

    const std::size_t n_keep = std::min(pop_size, static_cast<std::size_t>(std::round(pop_size * (params.n_best_keep / 100.0))));

    const std::size_t total_evaluations_target = pop_size * params.n_generations;
    const std::size_t total_batches_to_process = std::max<std::size_t>(
        num_vfpgas,
        (total_evaluations_target + offspring_per_batch - 1) / offspring_per_batch
    );

    auto init_end = std::chrono::steady_clock::now();
    summary.timings.cpu.init_time_ms = std::chrono::duration<double, std::milli>(init_end - init_start).count();

    const double initial_best = static_cast<double>(population_vec[0].fitness) / static_cast<double>(problem.scaling);
    summary.initial_best_fitness = initial_best;
    auto now_init = std::chrono::steady_clock::now();
    double init_elapsed_ms = std::chrono::duration<double, std::milli>(now_init - wall_start).count();
    summary.best_fitness_history.push_back({0, init_elapsed_ms, initial_best});
    double current_best_val = initial_best;
    summary.gen_best_found = 0;

    std::vector<WorkerTiming> worker_timings(num_vfpgas);
    for (std::size_t v = 0; v < num_vfpgas; ++v) {
        worker_timings[v].vfid = static_cast<int>(v);
    }

    std::vector<SafeQueue<BatchJob>> parent_queues(num_vfpgas);
    SafeQueue<BatchJob> offspring_queue;

    std::vector<std::thread> worker_threads;
    worker_threads.reserve(num_vfpgas);
    for (std::size_t v = 0; v < num_vfpgas; ++v) {
        worker_threads.emplace_back([v, &parent_queues, &offspring_queue, &execute_vfpga_batch, &worker_timings]() {
            while (true) {
                auto t_idle_start = std::chrono::steady_clock::now();
                auto job_opt = parent_queues[v].pop();
                auto t_idle_end = std::chrono::steady_clock::now();
                worker_timings[v].idle_time_ms += std::chrono::duration<double, std::milli>(t_idle_end - t_idle_start).count();

                if (!job_opt) {
                    break;
                }
                BatchJob job = std::move(*job_opt);

                auto t_act_start = std::chrono::steady_clock::now();
                execute_vfpga_batch(static_cast<int>(v), job);
                auto t_act_end = std::chrono::steady_clock::now();
                worker_timings[v].active_time_ms += std::chrono::duration<double, std::milli>(t_act_end - t_act_start).count();
                worker_timings[v].batches_processed++;

                offspring_queue.push(std::move(job));
            }
        });
    }

    std::vector<EncodedIndividual> parents1(batch_ind_per_stream);
    std::vector<EncodedIndividual> parents2(batch_ind_per_stream);
    std::vector<EncodedIndividual> batch_offspring(offspring_per_batch);

    uint32_t batches_dispatched = 0;
    uint32_t batches_completed = 0;

    for (const auto &slot : params.buffer_slots) {
        if (batches_dispatched >= total_batches_to_process) break;

        auto t0 = std::chrono::steady_clock::now();
        create_parent_pairs(population_vec, parents1, parents2, new_seed());
        population_to_buffer(parents1, slot.src_buf_0, problem.dimension);
        population_to_buffer(parents2, slot.src_buf_1, problem.dimension);
        auto t1 = std::chrono::steady_clock::now();
        summary.timings.cpu.parent_selection_ms += std::chrono::duration<double, std::milli>(t1 - t0).count();

        BatchJob job;
        job.batch_id = batches_dispatched++;
        job.batch_seed = new_seed();
        job.vfid = slot.vfid;
        job.slot_id = slot.slot_id;
        job.num_ind_per_stream = batch_ind_per_stream;
        job.src_buf_0 = slot.src_buf_0;
        job.src_buf_1 = slot.src_buf_1;
        job.dst_buf_0 = slot.dst_buf_0;
        job.dst_buf_1 = slot.dst_buf_1;
        job.parents1 = parents1;
        job.parents2 = parents2;

        parent_queues[job.vfid].push(std::move(job));
    }

    const std::size_t log_interval_batches = std::max<std::size_t>(1, total_batches_to_process / 10);

    while (batches_completed < total_batches_to_process) {
        auto t_wait_start = std::chrono::steady_clock::now();
        auto finished_job_opt = offspring_queue.pop_expected(batches_completed);
        auto t_wait_end = std::chrono::steady_clock::now();
        summary.timings.cpu.idle_time_ms += std::chrono::duration<double, std::milli>(t_wait_end - t_wait_start).count();

        if (!finished_job_opt) {
            break;
        }

        BatchJob finished_job = std::move(*finished_job_opt);
        batches_completed++;

        auto t_up_start = std::chrono::steady_clock::now();
        population_from_buffer(finished_job.dst_buf_0, finished_job.num_ind_per_stream, batch_offspring, problem.dimension, 0);
        population_from_buffer(finished_job.dst_buf_1, finished_job.num_ind_per_stream, batch_offspring, problem.dimension, finished_job.num_ind_per_stream);

        update_generation_with_parents(batch_offspring, finished_job.parents1, finished_job.parents2);

        update_population(population_vec, batch_offspring, next_population_vec, n_keep);
        std::swap(population_vec, next_population_vec);
        population_to_buffer(population_vec, params.buffer_pop, problem.dimension, true);
        auto t_up_end = std::chrono::steady_clock::now();
        summary.timings.cpu.population_update_ms += std::chrono::duration<double, std::milli>(t_up_end - t_up_start).count();

        const double current_best = static_cast<double>(population_vec[0].fitness) / static_cast<double>(problem.scaling);
        if ((batches_completed * offspring_per_batch) % pop_size == 0) {
            auto now_gen = std::chrono::steady_clock::now();
            double gen_elapsed_ms = std::chrono::duration<double, std::milli>(now_gen - wall_start).count();
            std::size_t completed_gen = (batches_completed * offspring_per_batch) / pop_size;
            summary.best_fitness_history.push_back({completed_gen, gen_elapsed_ms, current_best});
        }
        if (current_best < current_best_val) {
            current_best_val = current_best;
            summary.gen_best_found = (batches_completed * offspring_per_batch) / pop_size;
        }

        if (batches_dispatched < total_batches_to_process) {
            auto t_sel_start = std::chrono::steady_clock::now();
            create_parent_pairs(population_vec, parents1, parents2, new_seed());
            population_to_buffer(parents1, finished_job.src_buf_0, problem.dimension);
            population_to_buffer(parents2, finished_job.src_buf_1, problem.dimension);
            auto t_sel_end = std::chrono::steady_clock::now();
            summary.timings.cpu.parent_selection_ms += std::chrono::duration<double, std::milli>(t_sel_end - t_sel_start).count();

            finished_job.batch_id = batches_dispatched++;
            finished_job.batch_seed = new_seed();
            finished_job.parents1 = parents1;
            finished_job.parents2 = parents2;
            parent_queues[finished_job.vfid].push(std::move(finished_job));
        }

        if (batches_completed == 1 || batches_completed % log_interval_batches == 0 || batches_completed == total_batches_to_process) {
            std::cout << "Pipelined Batch " << batches_completed << "/" << total_batches_to_process
                      << " completed. Best fitness: " << current_best << std::endl;
        }
    }

    while (summary.best_fitness_history.size() <= params.n_generations) {
        std::size_t gen = summary.best_fitness_history.size();
        auto now_gen = std::chrono::steady_clock::now();
        double gen_elapsed_ms = std::chrono::duration<double, std::milli>(now_gen - wall_start).count();
        const double current_best = static_cast<double>(population_vec[0].fitness) / static_cast<double>(problem.scaling);
        summary.best_fitness_history.push_back({gen, gen_elapsed_ms, current_best});
    }

    for (std::size_t v = 0; v < num_vfpgas; ++v) {
        parent_queues[v].shutdown();
    }
    for (auto &worker : worker_threads) {
        if (worker.joinable()) {
            worker.join();
        }
    }

    auto wall_end = std::chrono::steady_clock::now();
    summary.timings.total_time_ms = std::chrono::duration<double, std::milli>(wall_end - wall_start).count();
    summary.timings.workers = std::move(worker_timings);
    summary.timings.cpu.active_time_ms = summary.timings.cpu.init_time_ms +
                                         summary.timings.cpu.parent_selection_ms +
                                         summary.timings.cpu.population_update_ms;

    validate_population(problem, population_vec);
    summary.best_individual = evaluate_population_exact_best(problem, population_vec, summary.exact_best_fitness);
    summary.best_fitness = static_cast<double>(summary.best_individual.fitness) / static_cast<double>(problem.scaling);

    return summary;
}
