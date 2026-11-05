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

#include "crossover.hpp"
#include "test_helper.hpp"

#include <cstring>
#include <iostream>
#include <vector>

#include "ga_encoding_constants.hpp"
#include "ga.hpp"
#include "ga_streaming.hpp"

static int kNumCities = 40;
static std::size_t kNumIndividuals = 3;
static std::uint32_t kFitness0Base = 1000;
static std::uint32_t kFitness1Base = 2000;

static int kDepotId = 1;

static std::vector<ProblemNode> make_nodes() {
    std::vector<ProblemNode> nodes(kNumCities);
    for (int i = 1; i <= kNumCities; ++i) {
        nodes[i-1] = ProblemNode{
           i,
           i & ((1 << COORD_BITS) - 1),
           (i * 2) & ((1 << COORD_BITS) - 1),
           i & ((1 << CAPACITY_BITS) - 1)
        };
    }
    return nodes;
}

static ProblemInstance make_problem() {
    ProblemInstance p;
    p.name = "tb_hardcoded";
    p.dimension = kNumCities + 1;
    p.capacity = (1 << CAPACITY_BITS) - 1;
    p.depot = ProblemNode{kDepotId, 0, 0, 0};
    p.nodes = make_nodes();
    return p;
}

static std::vector<std::vector<int>> kPop0Tours = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39}
};

static std::vector<std::vector<int>> kPop1Tours = {
    {39, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {10, 24, 6, 3, 22, 13, 29, 23, 33, 14, 38, 7, 21, 5, 32, 28, 25, 15, 36, 20, 37, 16, 39, 4, 9, 8, 30, 11, 1, 2, 26, 27, 17, 18, 19, 31, 34, 12, 35, 0}
};

static std::vector<std::vector<int>> kExpChild0Tours = {
    {34, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 0, 39, 38, 37, 36, 35},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {39, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 0, 38, 36, 37}
};

static std::vector<std::vector<int>> kExpChild1Tours = {
    {5, 38, 37, 36, 35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 39, 0, 1, 2, 3, 4},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39},
    {31, 24, 6, 3, 22, 13, 29, 23, 33, 14, 38, 7, 21, 5, 32, 28, 25, 15, 36, 20, 37, 16, 39, 4, 9, 8, 30, 11, 1, 2, 26, 27, 17, 18, 34, 35, 0, 10, 12, 19}
};

int run_crossover_test() {
    std::cout << "Crossover Unit Test" << std::endl;
    hls::stream_of_blocks<IndividualAsBeats> in0;
    hls::stream_of_blocks<IndividualAsBeats> out0;
    hls::stream_of_blocks<IndividualAsBeats> in1;
    hls::stream_of_blocks<IndividualAsBeats> out1;

    const ProblemInstance problem = make_problem();
    const std::vector<Individual> pop_0 = build_population(problem, kPop0Tours, kFitness0Base);
    const std::vector<Individual> pop_1 = build_population(problem, kPop1Tours, kFitness1Base);

    std::cout << "Streaming parents into block streams..." << std::endl;
    tb_push_individuals(in0, problem, pop_0);
    tb_push_individuals(in1, problem, pop_1);

    const CityIndex kOxStart = 1;
    const CityIndex kOxEnd = 33;
    hls::stream<CityPair> crossover_pairs("crossover_pairs");

    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        crossover_pairs.write(CityPair{kOxStart, kOxEnd});
    }

    std::cout << "Executing Crossover..." << std::endl;
    crossover(in0, in1, crossover_pairs, out0, out1,
              static_cast<int>(kNumIndividuals),
              kNumCities,
              100);

    std::cout << "Reading children from block streams..." << std::endl;
    const std::vector<Individual> child_0 = tb_pull_individuals(out0, problem, kNumIndividuals);
    const std::vector<Individual> child_1 = tb_pull_individuals(out1, problem, kNumIndividuals);
    const std::vector<Individual> exp_child_0 = build_population(problem, kExpChild0Tours, kFitness0Base);
    const std::vector<Individual> exp_child_1 = build_population(problem, kExpChild1Tours, kFitness1Base);

    std::cout << "Verifying Outputs..." << std::endl;
    int errors = 0;
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        if (child_0[i] != exp_child_0[i]) {
            std::cout << "Stream 0 indiv " << i << " mismatch:\n -g:"
                      << child_0[i] << "\n -e:" << exp_child_0[i] << std::endl;
            errors++;
        }
        if (child_1[i] != exp_child_1[i]) {
            std::cout << "Stream 1 indiv " << i << " mismatch:\n -g:"
                      << child_1[i] << "\n -e:" << exp_child_1[i] << std::endl;
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "TEST PASSED!" << std::endl;
    } else {
        std::cout << "TEST FAILED with " << errors << " errors." << std::endl;
    }

    return errors;
}

static int kNumCities_border_cases = 15;
static std::size_t kNumIndividuals_border_cases = 4;

static std::vector<ProblemNode> make_nodes_border_cases() {
    std::vector<ProblemNode> nodes(kNumCities_border_cases);
    for (int i = 1; i <= kNumCities_border_cases; ++i) {
        nodes[i-1] = ProblemNode{
           i,
           i & ((1 << COORD_BITS) - 1),
           (i * 2) & ((1 << COORD_BITS) - 1),
           i & ((1 << CAPACITY_BITS) - 1)
        };
    }
    return nodes;
}

static ProblemInstance make_problem_border_cases() {
    ProblemInstance p;
    p.name = "tb_border_cases";
    p.dimension = kNumCities_border_cases + 1;
    p.capacity = (1 << CAPACITY_BITS) - 1;
    p.depot = ProblemNode{kDepotId, 0, 0, 0};
    p.nodes = make_nodes_border_cases();
    return p;
}

static std::vector<std::vector<int>> kPop0Tours_border_cases = {
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}
};

static std::vector<std::vector<int>> kPop1Tours_border_cases = {
    {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
    {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
    {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
    {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
};

static std::vector<std::vector<int>> kExpChild0Tours_border_cases = {
    {14, 13, 12, 11, 10, 5, 6, 7, 8, 9, 4, 3, 2, 1, 0},
    {3, 2, 1, 0, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14},
    {0, 1, 2, 3, 4, 9, 8, 7, 6, 5, 14, 13, 12, 11, 10},
    {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14}
};

static std::vector<std::vector<int>> kExpChild1Tours_border_cases = {
    {0, 1, 2, 3, 4, 9, 8, 7, 6, 5, 10, 11, 12, 13, 14},
    {11, 12, 13, 14, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
    {14, 13, 12, 11, 10, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4},
    {14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0}
};

int run_crossover_test_border_cases() {
    std::cout << "Crossover Unit Test (Border Cases, 15 cities)" << std::endl;
    hls::stream_of_blocks<IndividualAsBeats> in0;
    hls::stream_of_blocks<IndividualAsBeats> out0;
    hls::stream_of_blocks<IndividualAsBeats> in1;
    hls::stream_of_blocks<IndividualAsBeats> out1;

    const ProblemInstance problem = make_problem_border_cases();
    const std::vector<Individual> pop_0 = build_population(problem, kPop0Tours_border_cases, kFitness0Base);
    const std::vector<Individual> pop_1 = build_population(problem, kPop1Tours_border_cases, kFitness1Base);

    std::cout << "Streaming parents into block streams..." << std::endl;
    tb_push_individuals(in0, problem, pop_0);
    tb_push_individuals(in1, problem, pop_1);

    hls::stream<CityPair> crossover_pairs("crossover_pairs_border_cases");
    const std::vector<CityPair> cut_points = {
        CityPair{5, 9},
        CityPair{4, 14},
        CityPair{0, 4},
        CityPair{0, 14}
    };

    for (std::size_t i = 0; i < kNumIndividuals_border_cases; ++i) {
        crossover_pairs.write(cut_points[i]);
    }

    std::cout << "Executing Crossover (border cases)..." << std::endl;
    crossover(in0, in1, crossover_pairs, out0, out1,
              static_cast<int>(kNumIndividuals_border_cases),
              kNumCities_border_cases,
              100);

    std::cout << "Reading children from block streams..." << std::endl;
    int errors = 0;
    std::vector<Individual> child_0;
    std::vector<Individual> child_1;
    try {
        child_0 = tb_pull_individuals(out0, problem, kNumIndividuals_border_cases);
        child_1 = tb_pull_individuals(out1, problem, kNumIndividuals_border_cases);
    } catch (const std::exception &e) {
        std::cout << "Exception decoding children (corrupted individual in border cases test): " << e.what() << std::endl;
        return 1;
    }

    const std::vector<Individual> exp_child_0 = build_population(problem, kExpChild0Tours_border_cases, kFitness0Base);
    const std::vector<Individual> exp_child_1 = build_population(problem, kExpChild1Tours_border_cases, kFitness1Base);

    std::cout << "Verifying Outputs..." << std::endl;
    for (std::size_t i = 0; i < kNumIndividuals_border_cases; ++i) {
        if (child_0[i] != exp_child_0[i]) {
            std::cout << "Stream 0 indiv " << i << " (cut [" << cut_points[i].start << ", " << cut_points[i].end << "]) mismatch:\n -g:"
                      << child_0[i] << "\n -e:" << exp_child_0[i] << std::endl;
            errors++;
        }
        if (child_1[i] != exp_child_1[i]) {
            std::cout << "Stream 1 indiv " << i << " (cut [" << cut_points[i].start << ", " << cut_points[i].end << "]) mismatch:\n -g:"
                      << child_1[i] << "\n -e:" << exp_child_1[i] << std::endl;
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "BORDER CASES CROSSOVER TEST PASSED!" << std::endl;
    } else {
        std::cout << "BORDER CASES CROSSOVER TEST FAILED with " << errors << " errors." << std::endl;
    }

    return errors;
}

int run_crossover_prob_zero_test() {
    std::cout << "Crossover Probability Zero Unit Test (prob=0 should copy parents)" << std::endl;
    hls::stream_of_blocks<IndividualAsBeats> in0;
    hls::stream_of_blocks<IndividualAsBeats> out0;
    hls::stream_of_blocks<IndividualAsBeats> in1;
    hls::stream_of_blocks<IndividualAsBeats> out1;

    const ProblemInstance problem = make_problem();
    const std::vector<Individual> pop_0 = build_population(problem, kPop0Tours, kFitness0Base);
    const std::vector<Individual> pop_1 = build_population(problem, kPop1Tours, kFitness1Base);

    tb_push_individuals(in0, problem, pop_0);
    tb_push_individuals(in1, problem, pop_1);

    hls::stream<CityPair> crossover_pairs("crossover_pairs_prob_zero");
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        crossover_pairs.write(CityPair(1, 33, 1));
    }

    crossover(in0, in1, crossover_pairs, out0, out1,
              static_cast<int>(kNumIndividuals),
              CityIndex(kNumCities),
              0);

    const std::vector<Individual> child_0 = tb_pull_individuals(out0, problem, kNumIndividuals);
    const std::vector<Individual> child_1 = tb_pull_individuals(out1, problem, kNumIndividuals);

    int errors = 0;
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        if (child_0[i] != pop_0[i]) {
            std::cout << "Stream 0 indiv " << i << " did not match parent 0 when prob=0\n";
            errors++;
        }
        if (child_1[i] != pop_1[i]) {
            std::cout << "Stream 1 indiv " << i << " did not match parent 1 when prob=0\n";
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "CROSSOVER PROB ZERO TEST PASSED!" << std::endl;
    } else {
        std::cout << "CROSSOVER PROB ZERO TEST FAILED with " << errors << " errors." << std::endl;
    }

    return errors;
}

int run_crossover_prob_100_test() {
    std::cout << "Crossover Probability 100 Unit Test (prob=100 should always apply crossover)" << std::endl;
    hls::stream_of_blocks<IndividualAsBeats> in0;
    hls::stream_of_blocks<IndividualAsBeats> out0;
    hls::stream_of_blocks<IndividualAsBeats> in1;
    hls::stream_of_blocks<IndividualAsBeats> out1;

    const ProblemInstance problem = make_problem();
    const std::vector<Individual> pop_0 = build_population(problem, kPop0Tours, kFitness0Base);
    const std::vector<Individual> pop_1 = build_population(problem, kPop1Tours, kFitness1Base);

    tb_push_individuals(in0, problem, pop_0);
    tb_push_individuals(in1, problem, pop_1);

    hls::stream<CityPair> crossover_pairs("crossover_pairs_prob_100");
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        crossover_pairs.write(CityPair(1, 33, 100));
    }

    crossover(in0, in1, crossover_pairs, out0, out1,
              static_cast<int>(kNumIndividuals),
              CityIndex(kNumCities),
              100);

    const std::vector<Individual> child_0 = tb_pull_individuals(out0, problem, kNumIndividuals);
    const std::vector<Individual> child_1 = tb_pull_individuals(out1, problem, kNumIndividuals);
    const std::vector<Individual> exp_child_0 = build_population(problem, kExpChild0Tours, kFitness0Base);
    const std::vector<Individual> exp_child_1 = build_population(problem, kExpChild1Tours, kFitness1Base);

    int errors = 0;
    for (std::size_t i = 0; i < kNumIndividuals; ++i) {
        if (child_0[i] != exp_child_0[i]) {
            std::cout << "Stream 0 indiv " << i << " did not match exp_child_0 when prob=100\n";
            errors++;
        }
        if (child_1[i] != exp_child_1[i]) {
            std::cout << "Stream 1 indiv " << i << " did not match exp_child_1 when prob=100\n";
            errors++;
        }
    }

    if (errors == 0) {
        std::cout << "CROSSOVER PROB 100 TEST PASSED!" << std::endl;
    } else {
        std::cout << "CROSSOVER PROB 100 TEST FAILED with " << errors << " errors." << std::endl;
    }

    return errors;
}
