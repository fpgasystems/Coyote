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
 * Standalone unit tests for update_population and create_parent_pairs in ga.cpp.
 *
 * Requirements:
 * - Bytes in EncodedIndividual are NOT set (set to nullptr).
 * - Explicitly creates input instances and expected output instances.
 * - No external dependencies.
 *
 * Build & Run:
 *   g++ -std=c++17 -I . ga_test.cpp ga.cpp ga_streaming.cpp -o ga_test && ./ga_test
 */

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "ga.hpp"
#include "ga_streaming.hpp"
#include "problem_parser.hpp"

namespace {

void print_population(const std::string &label, const std::vector<EncodedIndividual> &pop) {
    std::cout << label << " [size=" << pop.size() << "]: ";
    for (std::size_t i = 0; i < pop.size(); ++i) {
        std::cout << pop[i].fitness;
        if (i + 1 < pop.size()) std::cout << ", ";
    }
    std::cout << "\n";
}

bool check_population_equal(const std::string &test_name,
                            const std::vector<EncodedIndividual> &actual,
                            const std::vector<EncodedIndividual> &expected) {
    if (actual.size() != expected.size()) {
        std::cerr << "FAIL [" << test_name << "]: size mismatch. Actual: "
                  << actual.size() << ", Expected: " << expected.size() << "\n";
        print_population("  Actual  ", actual);
        print_population("  Expected", expected);
        return false;
    }

    bool match = true;
    for (std::size_t i = 0; i < actual.size(); ++i) {
        if (actual[i].fitness != expected[i].fitness) {
            std::cerr << "FAIL [" << test_name << "]: mismatch at index " << i
                      << ": actual fitness=" << actual[i].fitness
                      << ", expected fitness=" << expected[i].fitness << "\n";
            match = false;
        } else if (actual[i].bytes != expected[i].bytes && 
            !(actual[i].bytes != nullptr && expected[i].bytes != nullptr && *actual[i].bytes == *expected[i].bytes)) {
            std::cerr << "FAIL [" << test_name << "]: mismatch at index " << i
                      << ": actual bytes=" << static_cast<const void*>(actual[i].bytes);
            if (actual[i].bytes) std::cerr << " (*=" << static_cast<int>(*actual[i].bytes) << ")";
            std::cerr << ", expected bytes=" << static_cast<const void*>(expected[i].bytes);
            if (expected[i].bytes) std::cerr << " (*=" << static_cast<int>(*expected[i].bytes) << ")";
            std::cerr << "\n";
            match = false;
        }
    }

    if (!match) {
        print_population("  Actual  ", actual);
        print_population("  Expected", expected);
        return false;
    }

    std::cout << "PASS [" << test_name << "]\n";
    return true;
}

bool test_create_parent_pairs_seed_42() {
    const std::vector<EncodedIndividual> input_population = {
        {nullptr, 10},
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 40}
    };
    const std::uint32_t seed = 42;

    std::vector<EncodedIndividual> actual_parents1(input_population.size());
    std::vector<EncodedIndividual> actual_parents2(input_population.size());

    create_parent_pairs(input_population, actual_parents1, actual_parents2, seed);

    const std::vector<EncodedIndividual> expected_parents1 = {
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 10},
        {nullptr, 10}
    };
    const std::vector<EncodedIndividual> expected_parents2 = {
        {nullptr, 10},
        {nullptr, 30},
        {nullptr, 10},
        {nullptr, 20}
    };

    bool ok1 = check_population_equal("create_parent_pairs_seed_42 (parents1)", actual_parents1, expected_parents1);
    bool ok2 = check_population_equal("create_parent_pairs_seed_42 (parents2)", actual_parents2, expected_parents2);
    return ok1 && ok2;
}

bool test_create_parent_pairs_seed_12345() {
    const std::vector<EncodedIndividual> input_population = {
        {nullptr, 10},
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 40}
    };
    const std::uint32_t seed = 12345;

    std::vector<EncodedIndividual> actual_parents1(input_population.size());
    std::vector<EncodedIndividual> actual_parents2(input_population.size());

    create_parent_pairs(input_population, actual_parents1, actual_parents2, seed);

    const std::vector<EncodedIndividual> expected_parents1 = {
        {nullptr, 40},
        {nullptr, 10},
        {nullptr, 30},
        {nullptr, 20}
    };
    const std::vector<EncodedIndividual> expected_parents2 = {
        {nullptr, 10},
        {nullptr, 10},
        {nullptr, 30},
        {nullptr, 30}
    };

    bool ok1 = check_population_equal("create_parent_pairs_seed_12345 (parents1)", actual_parents1, expected_parents1);
    bool ok2 = check_population_equal("create_parent_pairs_seed_12345 (parents2)", actual_parents2, expected_parents2);
    return ok1 && ok2;
}

bool test_create_parent_pairs_homogeneous() {
    const std::vector<EncodedIndividual> input_population = {
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50}
    };
    const std::uint32_t seed = 999;

    std::vector<EncodedIndividual> actual_parents1(input_population.size());
    std::vector<EncodedIndividual> actual_parents2(input_population.size());

    create_parent_pairs(input_population, actual_parents1, actual_parents2, seed);

    const std::vector<EncodedIndividual> expected_parents1 = {
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50}
    };
    const std::vector<EncodedIndividual> expected_parents2 = {
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50},
        {nullptr, 50}
    };

    bool ok1 = check_population_equal("create_parent_pairs_homogeneous (parents1)", actual_parents1, expected_parents1);
    bool ok2 = check_population_equal("create_parent_pairs_homogeneous (parents2)", actual_parents2, expected_parents2);
    return ok1 && ok2;
}

bool test_update_population_better_new_generation() {
    std::vector<EncodedIndividual> input_population = {
        {nullptr, 100},
        {nullptr, 200},
        {nullptr, 300},
        {nullptr, 400}
    };
    std::vector<EncodedIndividual> input_new_generation = {
        {nullptr, 50},
        {nullptr, 150},
        {nullptr, 250},
        {nullptr, 350}
    };
    const int n_keep_best = 2;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    const std::vector<EncodedIndividual> expected_new_population = {
        {nullptr, 50},
        {nullptr, 100},
        {nullptr, 150},
        {nullptr, 250}
    };

    return check_population_equal("update_population_better_new_generation",
                                  actual_new_population, expected_new_population);
}

bool test_update_population_with_duplicates() {
    std::vector<EncodedIndividual> input_population = {
        {nullptr, 10},
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 40}
    };
    std::vector<EncodedIndividual> input_new_generation = {
        {nullptr, 15},
        {nullptr, 15},
        {nullptr, 25},
        {nullptr, 25}
    };
    const int n_keep_best = 2;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    const std::vector<EncodedIndividual> expected_new_population = {
        {nullptr, 10},
        {nullptr, 15},
        {nullptr, 20},
        {nullptr, 25}
    };

    return check_population_equal("update_population_with_duplicates",
                                  actual_new_population, expected_new_population);
}

bool test_update_population_equal_fitness_prefers_new() {
    const std::uint8_t byte_old = 2;
    const std::uint8_t byte_new = 1;

    std::vector<EncodedIndividual> input_population = {
        {&byte_old, 10},
        {nullptr, 20},
        {nullptr, 30}
    };
    std::vector<EncodedIndividual> input_new_generation = {
        {&byte_new, 10},
        {nullptr, 25},
        {nullptr, 35}
    };
    const int n_keep_best = 1;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    const std::vector<EncodedIndividual> expected_new_population = {
        {&byte_new, 10},
        {nullptr, 25},
        {nullptr, 35}
    };

    return check_population_equal("update_population_equal_fitness_prefers_new",
                                  actual_new_population, expected_new_population);
}

bool test_update_population_all_keep_best() {
    std::vector<EncodedIndividual> input_population = {
        {nullptr, 10},
        {nullptr, 30},
        {nullptr, 50},
        {nullptr, 70}
    };
    std::vector<EncodedIndividual> input_new_generation = {
        {nullptr, 20},
        {nullptr, 40},
        {nullptr, 60},
        {nullptr, 80}
    };
    const int n_keep_best = 4;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    // Keeps the best 4 across both: 10, 20, 30, 40.
    const std::vector<EncodedIndividual> expected_new_population = {
        {nullptr, 10},
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 40}
    };

    return check_population_equal("update_population_all_keep_best",
                                  actual_new_population, expected_new_population);
}

bool test_update_population_zero_keep_best() {
    std::vector<EncodedIndividual> input_population = {
        {nullptr, 10},
        {nullptr, 20},
        {nullptr, 30},
        {nullptr, 40}
    };
    std::vector<EncodedIndividual> input_new_generation = {
        {nullptr, 5},
        {nullptr, 15},
        {nullptr, 25},
        {nullptr, 35}
    };
    const int n_keep_best = 0;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    const std::vector<EncodedIndividual> expected_new_population = {
        {nullptr, 5},
        {nullptr, 15},
        {nullptr, 25},
        {nullptr, 35}
    };

    return check_population_equal("update_population_zero_keep_best",
                                  actual_new_population, expected_new_population);
}

bool test_update_population_unsorted_new_generation() {
    std::vector<EncodedIndividual> input_population = {
        {nullptr, 100},
        {nullptr, 200},
        {nullptr, 300},
        {nullptr, 400}
    };
    // new_generation provided in unsorted order
    std::vector<EncodedIndividual> input_new_generation = {
        {nullptr, 350},
        {nullptr, 50},
        {nullptr, 250},
        {nullptr, 150}
    };
    const int n_keep_best = 2;

    std::vector<EncodedIndividual> actual_new_population(input_population.size());
    update_population(input_population, input_new_generation, actual_new_population, n_keep_best);

    const std::vector<EncodedIndividual> expected_new_population = {
        {nullptr, 50},
        {nullptr, 100},
        {nullptr, 150},
        {nullptr, 250}
    };

    return check_population_equal("update_population_unsorted_new_generation",
                                  actual_new_population, expected_new_population);
}

bool test_run_ga_in_place_buffer_shift() {
    ProblemInstance problem;
    problem.name = "Test5";
    problem.capacity = 100;
    problem.dimension = 5;
    problem.depot = ProblemNode{0, 0, 0, 0};
    problem.nodes = {
        ProblemNode{0, 0, 0, 0},
        ProblemNode{1, 10, 0, 10},
        ProblemNode{2, 25, 20, 10},
        ProblemNode{3, 10, 40, 10},
        ProblemNode{4, 0, 20, 10}
    };

    const std::size_t multiplier = 1;
    std::size_t pop_size = problem.dimension * multiplier; // 5 -> 6 (even)
    if (pop_size % 2 != 0) pop_size += 1;
    const std::size_t half_pop = pop_size / 2; // 3
    const int beats_per_ind = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_ind = beats_per_ind * AXI_BYTES;
    const std::size_t total_bytes = pop_size * bytes_per_ind;
    const std::size_t half_bytes = half_pop * bytes_per_ind;

    std::vector<std::uint8_t> src_0(half_bytes, 0);
    std::vector<std::uint8_t> src_1(half_bytes, 0);
    std::vector<std::uint8_t> dst_0(half_bytes, 0);
    std::vector<std::uint8_t> dst_1(half_bytes, 0);
    std::vector<std::uint8_t> pop_buf(total_bytes, 0);

    GAParams params;
    params.pop_size = pop_size;
    params.n_generations = 1;
    params.n_best_keep = 33.333333; // 2 out of 6 individuals = 33.33%
    params.seed = 42;
    params.buffer_src_0 = src_0.data();
    params.buffer_src_1 = src_1.data();
    params.buffer_dst_0 = dst_0.data();
    params.buffer_dst_1 = dst_1.data();
    params.buffer_pop   = pop_buf.data();

    Individual parent0_before;
    Individual parent1_before;
    bool mock_called = false;

    auto mock_new_gen = [&]() {
        mock_called = true;

        // 1. Capture initial parents 0 and 1 from pop_buf before any update happens
        parent0_before = decode_individual_fixed(problem, params.buffer_pop + 0 * bytes_per_ind);
        parent1_before = decode_individual_fixed(problem, params.buffer_pop + 1 * bytes_per_ind);

        // 2. Supply offspring across stream 0 and stream 1
        // Parent 0 has fitness 111, Parent 1 has fitness 123.
        std::vector<Individual> offspring_0 = {
            build_individual(problem, {4, 3, 2, 1, 0}), // fitness 102 (< 111)
            build_individual(problem, {0, 1, 4, 3, 2}), // fitness 111 (== 111)
            build_individual(problem, {1, 3, 2, 0, 4})  // fitness 147 (> 111)
        };
        std::vector<Individual> offspring_1 = {
            build_individual(problem, {1, 3, 4, 0, 2}), // fitness 156
            build_individual(problem, {2, 0, 3, 1, 4}), // fitness 187
            build_individual(problem, {2, 0, 3, 1, 4})  // fitness 187 (duplicate)
        };
        auto enc_0 = encode_population_fixed(problem, offspring_0);
        auto enc_1 = encode_population_fixed(problem, offspring_1);
        std::memcpy(params.buffer_dst_0, enc_0.data(), enc_0.size());
        std::memcpy(params.buffer_dst_1, enc_1.data(), enc_1.size());
    };

    GASummary summary = run_ga(problem, params, mock_new_gen);

    if (!mock_called) {
        std::cerr << "FAIL [run_ga_in_place_buffer_shift]: mock_new_gen was not called\n";
        return false;
    }

    // Verify initial parents had the expected fitnesses
    if (parent0_before.fitness != 111 || parent1_before.fitness != 123) {
        std::cerr << "FAIL [run_ga_in_place_buffer_shift]: initial parent fitness mismatch: p0="
                  << parent0_before.fitness << ", p1=" << parent1_before.fitness << "\n";
        return false;
    }

    // Expected final layout in pop_buf with parent fallback:
    // Slot 0: Offspring (fitness 102)
    // Slot 1: Parent 0 (fitness 111)   <- Shifted from slot 0 to slot 1 (j=1 > i=0)
    // Slot 2: Offspring (fitness 111)
    // Slot 3: Parent 1 (fitness 123)   <- Shifted from slot 1 to slot 3 (j=3 > i=1)
    // Slot 4: Population member (fitness 133)
    // Slot 5: Population member (fitness 150)
    const std::vector<std::uint32_t> expected_fitnesses = {102, 111, 111, 123, 133, 150};

    for (std::size_t i = 0; i < pop_size; ++i) {
        Individual ind = decode_individual_fixed(problem, params.buffer_pop + i * bytes_per_ind);
        if (ind.fitness != expected_fitnesses[i]) {
            std::cerr << "FAIL [run_ga_in_place_buffer_shift]: slot " << i << " fitness="
                      << ind.fitness << ", expected=" << expected_fitnesses[i] << "\n";
            return false;
        }
        if (compute_fitness(problem, ind) != ind.fitness) {
            std::cerr << "FAIL [run_ga_in_place_buffer_shift]: slot " << i << " fitness mismatch with tour\n";
            return false;
        }
    }

    // Check that Parent 0 shifted from slot 0 to slot 1 and preserved its exact tour
    Individual slot1 = decode_individual_fixed(problem, params.buffer_pop + 1 * bytes_per_ind);
    if (!(slot1 == parent0_before)) {
        std::cerr << "FAIL [run_ga_in_place_buffer_shift]: slot 1 corrupted, does not match Parent 0\n";
        return false;
    }

    // Check that Parent 1 shifted from slot 1 to slot 3 and preserved its exact tour
    Individual slot3 = decode_individual_fixed(problem, params.buffer_pop + 3 * bytes_per_ind);
    if (!(slot3 == parent1_before)) {
        std::cerr << "FAIL [run_ga_in_place_buffer_shift]: slot 3 corrupted, does not match Parent 1\n";
        return false;
    }

    std::cout << "PASS [run_ga_in_place_buffer_shift]\n";
    return true;
}

bool test_update_generation_with_parents() {
    const uint8_t dummy1 = 1, dummy2 = 2, dummy3 = 3, dummy4 = 4;
    std::vector<EncodedIndividual> parents1 = {
        {&dummy1, 50, 1001},
        {&dummy2, 70, 1002}
    };
    std::vector<EncodedIndividual> parents2 = {
        {&dummy3, 60, 2001},
        {&dummy4, 40, 2002}
    };

    // stream 0, child 0: fitness 45 (< 50, strictly better -> admit child)
    // stream 0, child 1: fitness 80 (>= 70, worse -> keep parent 1)
    // stream 1, child 0: fitness 60 (>= 60, equal -> keep parent 0)
    // stream 1, child 1: fitness 35 (< 40, strictly better -> admit child)
    const uint8_t c0 = 10, c1 = 11, c2 = 12, c3 = 13;
    std::vector<EncodedIndividual> offspring = {
        {&c0, 45, 3001},
        {&c1, 80, 3002},
        {&c2, 60, 3003},
        {&c3, 35, 3004}
    };

    update_generation_with_parents(offspring, parents1, parents2);

    if (offspring[0].fitness != 45 || offspring[0].bytes != &c0) {
        std::cerr << "FAIL [test_update_generation_with_parents]: stream 0 child 0 should be admitted\n";
        return false;
    }
    if (offspring[1].fitness != 70 || offspring[1].bytes != &dummy2) {
        std::cerr << "FAIL [test_update_generation_with_parents]: stream 0 child 1 should be replaced by parent 1\n";
        return false;
    }
    if (offspring[2].fitness != 60 || offspring[2].bytes != &dummy3) {
        std::cerr << "FAIL [test_update_generation_with_parents]: stream 1 child 0 should be replaced by parent 0\n";
        return false;
    }
    if (offspring[3].fitness != 35 || offspring[3].bytes != &c3) {
        std::cerr << "FAIL [test_update_generation_with_parents]: stream 1 child 1 should be admitted\n";
        return false;
    }

    std::cout << "PASS [test_update_generation_with_parents]\n";
    return true;
}

static ProblemInstance make_test_problem(int num_cities, int max_coord, int capacity, int max_demand) {
    ProblemInstance p;
    p.name = "test_problem";
    p.dimension = num_cities + 1;
    p.capacity = capacity;
    p.depot = ProblemNode{0, max_coord / 2, max_coord / 2, 0};
    p.nodes.resize(num_cities);
    for (int i = 0; i < num_cities; ++i) {
        p.nodes[i] = ProblemNode{i, max_coord, max_coord, max_demand};
    }
    return p;
}

bool test_validate_constants_valid() {
    ProblemInstance p = make_test_problem(20, 500, 100, 10);
    if (!validate_encoding_constants(p, false)) {
        std::cerr << "FAIL [test_validate_constants_valid]: expected true for valid problem\n";
        return false;
    }
    try {
        validate_encoding_constants(p, true);
    } catch (...) {
        std::cerr << "FAIL [test_validate_constants_valid]: threw exception for valid problem\n";
        return false;
    }
    std::cout << "PASS [test_validate_constants_valid]\n";
    return true;
}

bool test_validate_constants_coord_overflow() {
    ProblemInstance p = make_test_problem(20, 1 << COORD_BITS, 100, 10);
    std::ostringstream oss;
    auto *old_buf = std::cout.rdbuf(oss.rdbuf());
    bool ok = !validate_encoding_constants(p, false);
    bool threw = false;
    try {
        validate_encoding_constants(p, true);
    } catch (const std::runtime_error &) {
        threw = true;
    }
    std::cout.rdbuf(old_buf);

    if (!ok) {
        std::cerr << "FAIL [test_validate_constants_coord_overflow]: expected false\n";
        return false;
    }
    if (!threw) {
        std::cerr << "FAIL [test_validate_constants_coord_overflow]: expected throw\n";
        return false;
    }
    if (oss.str().find("COORD_BITS") == std::string::npos) {
        std::cerr << "FAIL [test_validate_constants_coord_overflow]: missing COORD_BITS in message\n";
        return false;
    }
    std::cout << "PASS [test_validate_constants_coord_overflow]\n";
    return true;
}

bool test_validate_constants_capacity_overflow() {
    ProblemInstance p = make_test_problem(20, 500, 1 << CAPACITY_BITS, 10);
    std::ostringstream oss;
    auto *old_buf = std::cout.rdbuf(oss.rdbuf());
    bool ok = !validate_encoding_constants(p, false);
    bool threw = false;
    try {
        validate_encoding_constants(p, true);
    } catch (const std::runtime_error &) {
        threw = true;
    }
    std::cout.rdbuf(old_buf);

    if (!ok) {
        std::cerr << "FAIL [test_validate_constants_capacity_overflow]: expected false\n";
        return false;
    }
    if (!threw) {
        std::cerr << "FAIL [test_validate_constants_capacity_overflow]: expected throw\n";
        return false;
    }
    if (oss.str().find("CAPACITY_BITS") == std::string::npos) {
        std::cerr << "FAIL [test_validate_constants_capacity_overflow]: missing CAPACITY_BITS in message\n";
        return false;
    }
    std::cout << "PASS [test_validate_constants_capacity_overflow]\n";
    return true;
}

bool test_validate_constants_demand_overflow() {
    ProblemInstance p = make_test_problem(20, 500, 100, 1 << CAPACITY_BITS);
    std::ostringstream oss;
    auto *old_buf = std::cout.rdbuf(oss.rdbuf());
    bool ok = !validate_encoding_constants(p, false);
    bool threw = false;
    try {
        validate_encoding_constants(p, true);
    } catch (const std::runtime_error &) {
        threw = true;
    }
    std::cout.rdbuf(old_buf);

    if (!ok) {
        std::cerr << "FAIL [test_validate_constants_demand_overflow]: expected false\n";
        return false;
    }
    if (!threw) {
        std::cerr << "FAIL [test_validate_constants_demand_overflow]: expected throw\n";
        return false;
    }
    if (oss.str().find("CAPACITY_BITS") == std::string::npos) {
        std::cerr << "FAIL [test_validate_constants_demand_overflow]: missing CAPACITY_BITS in message\n";
        return false;
    }
    std::cout << "PASS [test_validate_constants_demand_overflow]\n";
    return true;
}

bool test_validate_constants_max_cities_overflow() {
    ProblemInstance p = make_test_problem(MAX_CITIES + 1, 50, 100, 10);
    std::ostringstream oss;
    auto *old_buf = std::cout.rdbuf(oss.rdbuf());
    bool ok = !validate_encoding_constants(p, false);
    bool threw = false;
    try {
        validate_encoding_constants(p, true);
    } catch (const std::runtime_error &) {
        threw = true;
    }
    std::cout.rdbuf(old_buf);

    if (!ok) {
        std::cerr << "FAIL [test_validate_constants_max_cities_overflow]: expected false\n";
        return false;
    }
    if (!threw) {
        std::cerr << "FAIL [test_validate_constants_max_cities_overflow]: expected throw\n";
        return false;
    }
    if (oss.str().find("MAX_CITIES") == std::string::npos && oss.str().find("MAX_CACHE_ENTRIES") == std::string::npos) {
        std::cerr << "FAIL [test_validate_constants_max_cities_overflow]: missing MAX_CITIES/MAX_CACHE_ENTRIES in message\n";
        return false;
    }
    std::cout << "PASS [test_validate_constants_max_cities_overflow]\n";
    return true;
}

bool test_calculate_highest_precision() {
    // P-n40-k5: span_x = 58, span_y = 59, dimension = 40 (num_cities = 39)
    // max_coord = (1 << 20) - 1 = 1048575. 1048575 / 59 = 17772.
    int p40 = calculate_highest_precision(58.0, 59.0, 40);
    if (p40 != 17772) {
        std::cerr << "FAIL [test_calculate_highest_precision]: expected 17772 for P-n40-k5 params, got " << p40 << "\n";
        return false;
    }

    // P-n16-k8: span_x = 35, span_y = 42, dimension = 16 (num_cities = 15)
    // 1048575 / 42 = 24966.
    int p16 = calculate_highest_precision(35.0, 42.0, 16);
    if (p16 != 24966) {
        std::cerr << "FAIL [test_calculate_highest_precision]: expected 24966 for P-n16-k8 params, got " << p16 << "\n";
        return false;
    }

    // Edge case: zero span
    int p_zero = calculate_highest_precision(0.0, 0.0, 10);
    if (p_zero != (1 << COORD_BITS) - 1) {
        std::cerr << "FAIL [test_calculate_highest_precision]: expected max_coord for zero span, got " << p_zero << "\n";
        return false;
    }

    // Edge case: span larger than max_coord returns 1
    int p_large = calculate_highest_precision(1 << (COORD_BITS + 1), 10.0, 10);
    if (p_large != 1) {
        std::cerr << "FAIL [test_calculate_highest_precision]: expected 1 for oversized span, got " << p_large << "\n";
        return false;
    }

    std::cout << "PASS [test_calculate_highest_precision]\n";
    return true;
}

} // namespace

int main() {
    std::cout << "========================================\n";
    std::cout << "Running GA Unit Tests (ga_test.cpp)\n";
    std::cout << "========================================\n\n";

    int passed = 0;
    int total = 0;

    auto run = [&](const std::string &name, bool (*fn)()) {
        total++;
        std::cout << "Test " << total << ": " << name << "\n";
        if (fn()) {
            passed++;
        }
        std::cout << "\n";
    };

    run("create_parent_pairs (seed 42)", test_create_parent_pairs_seed_42);
    run("create_parent_pairs (seed 12345)", test_create_parent_pairs_seed_12345);
    run("create_parent_pairs (homogeneous population)", test_create_parent_pairs_homogeneous);

    run("update_population (better new generation)", test_update_population_better_new_generation);
    run("update_population (duplicate elimination & fallback)", test_update_population_with_duplicates);
    run("update_population (equal fitness preference)", test_update_population_equal_fitness_prefers_new);
    run("update_population (all keep best)", test_update_population_all_keep_best);
    run("update_population (zero keep best)", test_update_population_zero_keep_best);
    run("update_population (unsorted new generation)", test_update_population_unsorted_new_generation);

    run("run_ga (in-place pop_buffer shift integrity)", test_run_ga_in_place_buffer_shift);
    run("update_generation_with_parents (parent fallback)", test_update_generation_with_parents);

    run("validate_encoding_constants (valid instance)", test_validate_constants_valid);
    run("validate_encoding_constants (coord overflow)", test_validate_constants_coord_overflow);
    run("validate_encoding_constants (capacity overflow)", test_validate_constants_capacity_overflow);
    run("validate_encoding_constants (demand overflow)", test_validate_constants_demand_overflow);
    run("validate_encoding_constants (max_cities overflow)", test_validate_constants_max_cities_overflow);

    run("calculate_highest_precision", test_calculate_highest_precision);

    std::cout << "========================================\n";
    std::cout << "Result: " << passed << " / " << total << " tests passed.\n";
    std::cout << "========================================\n";

    return (passed == total) ? EXIT_SUCCESS : EXIT_FAILURE;
}

