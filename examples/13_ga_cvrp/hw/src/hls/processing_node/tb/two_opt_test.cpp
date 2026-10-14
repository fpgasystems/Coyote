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

#include "two_opt.hpp"
#include "two_opt_test.hpp"
#include "util.hpp"
#include "test_helper.hpp"

#include <iostream>
#include <vector>
#include <random>

#include "ga.hpp"
#include "ga_encoding_constants.hpp"

static constexpr int kNumCities = 40;
static constexpr int kNumIndividuals = 2;
static constexpr int kVehicleCapacity = 19;
static constexpr int kTwoOptK = 4;
static constexpr int seed = 17;

static std::vector<std::vector<int>> tours = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
};

static ProblemInstance make_problem() {
    ProblemInstance problem;
    problem.name = "two_opt_test";
    problem.dimension = kNumCities + 1;
    problem.capacity = kVehicleCapacity;
    problem.depot = ProblemNode{0, 42, 42, 0};
    problem.nodes.resize(kNumCities);

    std::mt19937 gen(seed);
    std::uniform_int_distribution<std::size_t> dist(0, (1 << COORD_BITS) - 1);
    
    for (int city = 0; city < kNumCities; ++city) {
        problem.nodes[city] = ProblemNode{city, dist(gen), dist(gen), dist(gen) % (kVehicleCapacity + 1)};
    }
    return problem;
}

// Simple software 2-opt implementation
static void two_opt_software(
    Individual &ind,
    std::vector<xoroshiro128plusplus> &worker_rngs,
    int &worker_idx,
    const ProblemInstance &problem,
    CityIndex two_opt_k,
    bool enable_precheck = false
) {
    const int DEPOT = problem.dimension - 1;
    auto get_coord_sw = [&](int node) -> Point {
        if (node == DEPOT) return {Coord(problem.depot.x), Coord(problem.depot.y)};
        return {Coord(problem.nodes[node].x), Coord(problem.nodes[node].y)};
    };

    long long total_delta = 0;
    size_t subtour_start = 0;

    while (subtour_start < ind.tour.size()) {
        size_t subtour_end = subtour_start;
        while (subtour_end < ind.tour.size() && !ind.tour[subtour_end].depot_after) {
            subtour_end++;
        }
        if (subtour_end == ind.tour.size()) subtour_end--;

        int subtour_len = subtour_end - subtour_start + 1;

        std::vector<int> sub(subtour_len);
        for (int i = 0; i < subtour_len; ++i) {
            sub[i] = ind.tour[subtour_start + i].node_id;
        }

        int w = worker_idx;
        worker_idx = (worker_idx == N_TWO_OPT_WORKERS - 1) ? 0 : (worker_idx + 1);

        for (CityIndex m = 0; m < two_opt_k; ++m) {
            uint32_t r1, r2;
            worker_rngs[w].nextPair(subtour_len, r1, r2);

            if (subtour_len >= 3) {
                int L_rel = r1;
                int R_rel = r2;
                if (L_rel > R_rel) std::swap(L_rel, R_rel);

                if (L_rel != R_rel) {
                    int M = (R_rel - L_rel + 1) / 2;

                    int prev_node_left  = (L_rel == 0) ? DEPOT : sub[L_rel - 1];
                    int prev_node_right = (R_rel == subtour_len - 1) ? DEPOT : sub[R_rel + 1];

                    Point prev_coord_left  = get_coord_sw(prev_node_left);
                    Point prev_coord_right = get_coord_sw(prev_node_right);

                    if (enable_precheck) {
                        int curr_left0 = sub[L_rel];
                        int curr_right0 = sub[R_rel];
                        Point curr_coord_left0 = get_coord_sw(curr_left0);
                        Point curr_coord_right0 = get_coord_sw(curr_right0);

                        Fitness d_old_left0  = floored_distance(prev_coord_left, curr_coord_left0);
                        Fitness d_old_right0 = floored_distance(curr_coord_right0, prev_coord_right);
                        Fitness d_new_left0  = floored_distance(prev_coord_left, curr_coord_right0);
                        Fitness d_new_right0 = floored_distance(curr_coord_left0, prev_coord_right);

                        long long delta0 = (long long)(d_old_left0 + d_old_right0) - (long long)(d_new_left0 + d_new_right0);
                        if (delta0 <= 0) {
                            continue;
                        }
                    }

                    std::vector<bool> improves(M, false);
                    for (int i = 0; i < M; ++i) {
                        int curr_left = sub[L_rel + i];
                        int curr_right = sub[R_rel - i];
                        Point curr_coord_left = get_coord_sw(curr_left);
                        Point curr_coord_right = get_coord_sw(curr_right);

                        Fitness d_old_left  = floored_distance(prev_coord_left, curr_coord_left);
                        Fitness d_old_right = floored_distance(curr_coord_right, prev_coord_right);
                        Fitness d_new_left  = floored_distance(prev_coord_left, curr_coord_right);
                        Fitness d_new_right = floored_distance(curr_coord_left, prev_coord_right);

                        long long delta = (long long)(d_old_left + d_old_right) - (long long)(d_new_left + d_new_right);
                        improves[i] = (delta > 0);
                        if (improves[i]) total_delta += delta;

                        prev_coord_left = curr_coord_left;
                        prev_coord_right = curr_coord_right;
                    }

                    bool swap_flag = false;
                    for (int i = 0; i < M; ++i) {
                        swap_flag ^= improves[i];
                        if (swap_flag) {
                            std::swap(sub[L_rel + i], sub[R_rel - i]);
                        }
                    }
                }
            }
        }

        for (int i = 0; i < subtour_len; ++i) {
            ind.tour[subtour_start + i].node_id = sub[i];
            ind.tour[subtour_start + i].depot_after = (i == subtour_len - 1);
        }

        subtour_start = subtour_end + 1;
    }

    ind.fitness -= total_delta;
}

int run_two_opt_test() {
    std::cout << "Two-Opt Unit Test" << std::endl;

    hls::stream_of_blocks<IndividualAsBeats> input;
    hls::stream_of_blocks<IndividualAsBeats> output;
    
    const ProblemInstance problem = make_problem();
    
    std::vector<Individual> input_population = build_population(problem, tours, 0);
    // Subtours of length 5
    for (auto &ind : input_population) {
        for (int i = 0; i < kNumCities; ++i) {
            ind.tour[i].depot_after = (i % 5 == 4);
        }
        ind.tour[kNumCities - 1].depot_after = true;
        ind.fitness = compute_fitness(problem, ind);
    }

    CityData cache[MAX_CACHE_ENTRIES];
    for (std::size_t i = 0; i < problem.nodes.size(); ++i) {
        cache[i] = CityData{
            Point{Coord(problem.nodes[i].x), Coord(problem.nodes[i].y)},
            Capacity(problem.nodes[i].demand)
        };
    }
    cache[kNumCities] = CityData{
        Point{Coord(problem.depot.x), Coord(problem.depot.y)},
        0
    };

    tb_push_individuals(input, problem, input_population);

    const uint32_t seed_two_opt = 42;
    
    two_opt(input, output, kNumIndividuals, CityIndex(kNumCities), CityIndex(kTwoOptK), false, cache, seed_two_opt);

    const std::vector<Individual> result = tb_pull_individuals(output, problem, kNumIndividuals);
    
    std::vector<Individual> expected_population = input_population;
    std::vector<xoroshiro128plusplus> sw_rngs(N_TWO_OPT_WORKERS);
    for (int w = 0; w < N_TWO_OPT_WORKERS; ++w) {
        uint32_t offset = static_cast<uint32_t>(w) * 0x9E3779B9u;
        sw_rngs[w].init(seed_two_opt ^ offset);
    }
    int worker_idx = 0;
    for (int i = 0; i < kNumIndividuals; ++i) {
        two_opt_software(expected_population[i], sw_rngs, worker_idx, problem, CityIndex(kTwoOptK), false);
    }

    std::cout << "Verifying Outputs..." << std::endl;
    int errors = 0;
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        if (result[i] != expected_population[i]) {
            std::cout << "Indiv " << i << " mismatch:\n -g:"
                      << result[i] << "\n -e:" << expected_population[i] << std::endl;
            errors++;
        }

        uint32_t expected_fitness = compute_fitness(problem, result[i]);
        if (result[i].fitness != expected_fitness) {
            std::cout << "Indiv " << i << " fitness mismatch: got "
                      << result[i].fitness << ", expected " << expected_fitness
                      << " (from compute_fitness)" << std::endl;
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "TWO OPT TEST PASSED!" << std::endl;
    } else {
        std::cout << "TWO OPT TEST FAILED with " << errors << " errors." << std::endl;
    }

    return errors;
}
