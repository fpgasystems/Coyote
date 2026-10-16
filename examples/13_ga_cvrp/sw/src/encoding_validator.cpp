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

#include "encoding_validator.hpp"
#include "ga_encoding_constants.hpp"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

template <typename T>
static inline int bit_width(T n) {
    if (n <= 0) return 0;
    if constexpr (sizeof(T) <= sizeof(unsigned int)) {
        return 32 - __builtin_clz(static_cast<unsigned int>(n));
    } else {
        return 64 - __builtin_clzll(static_cast<unsigned long long>(n));
    }
}

bool validate_encoding_constants(const ProblemInstance &problem, bool throw_on_error) {
    int max_trans_x = problem.depot.x;
    int max_trans_y = problem.depot.y;
    int max_demand = 0;
    for (const auto &node : problem.nodes) {
        max_trans_x = std::max(max_trans_x, node.x);
        max_trans_y = std::max(max_trans_y, node.y);
        max_demand = std::max(max_demand, node.demand);
    }

    bool failed = false;

    int expected_coord_bits = bit_width(std::max(max_trans_x, max_trans_y));
    if (COORD_BITS < expected_coord_bits) {
        std::cout << "COORD_BITS is too small for the given problem instance. Required: " + std::to_string(expected_coord_bits) << std::endl;
        failed = true;
    }

    int expected_capacity_bits = bit_width(problem.capacity);
    if (CAPACITY_BITS < expected_capacity_bits) {
        std::cout << "CAPACITY_BITS is too small for the given problem instance (max capacity must fit in). Required: " + std::to_string(expected_capacity_bits) << std::endl;
        failed = true;
    }

    int expected_demand_bits = bit_width(max_demand);
    if (CAPACITY_BITS < expected_demand_bits) {
        std::cout << "CAPACITY_BITS is too small for the given problem instance (max demand must fit in). Required: " + std::to_string(expected_demand_bits) << std::endl;
        failed = true;
    }

    int num_cities = problem.dimension - 1;
    if (MAX_CITIES < num_cities) {
        std::cout << "MAX_CITIES is too small for the given problem instance. Required: " + std::to_string(num_cities) << std::endl;
        failed = true;
    }

    int total_cache_entries = num_cities + 1;
    if (MAX_CACHE_ENTRIES < total_cache_entries) {
        std::cout << "MAX_CACHE_ENTRIES is too small for the given problem instance. Required: " + std::to_string(total_cache_entries) << std::endl;
        failed = true;
    }

    uint64_t max_fitness = static_cast<uint64_t>(2.0 * std::ceil(std::sqrt(static_cast<double>(max_trans_x) * max_trans_x + static_cast<double>(max_trans_y) * max_trans_y)) * (problem.dimension - 1));
    int expected_fitness_bits = bit_width(max_fitness);
    if (FITNESS_BITS < expected_fitness_bits) {
        std::cout << "FITNESS_BITS is too small for the given problem instance (max fitness must fit in). Required: " + std::to_string(expected_fitness_bits) << std::endl;
        failed = true;
    }

    int req_node_id_bits = std::max<int>(1, bit_width(std::max<int>(MAX_CITIES, num_cities)));
    int req_capacity_bits = std::max({(int)CAPACITY_BITS, expected_capacity_bits, expected_demand_bits});
    int req_coord_bits = std::max<int>(COORD_BITS, expected_coord_bits);
    int req_packed_bits = DEPOT_BITS + req_node_id_bits;
    if (CITY_BITS < req_packed_bits) {
        std::cout << "CITY_BITS is too small for packed city field. Required: " + std::to_string(req_packed_bits) << std::endl;
        failed = true;
    }

    int req_cache_entry_bits = 2 * req_coord_bits + req_capacity_bits;
    if (NODE_CACHE_ENTRY_BITS < req_cache_entry_bits) {
        std::cout << "NODE_CACHE_ENTRY_BITS is too small for cache entry. Required: " + std::to_string(req_cache_entry_bits) << std::endl;
        failed = true;
    }

    if (failed) {
        int new_coord_bits = req_coord_bits;
        int new_capacity_bits = req_capacity_bits;
        int new_node_id_bits = std::max<int>(NODE_ID_BITS, req_node_id_bits);
        int new_max_cities = std::max<int>(MAX_CITIES, (1 << new_node_id_bits) - 1);

        int new_city_bits = CITY_BITS;
        while (new_city_bits < DEPOT_BITS + new_node_id_bits) {
            new_city_bits *= 2;
        }
        int new_fitness_bits = std::max<int>(FITNESS_BITS, expected_fitness_bits);

        int new_city_bits_log2 = static_cast<int>(std::log2(new_city_bits));
        int new_axi_beat_width = AXI_BEAT_WIDTH;
        int new_axi_bytes = new_axi_beat_width / 8;
        int new_axi_cities_per_beat = new_axi_beat_width / new_city_bits;
        int new_axi_cities_per_beat_log2 = static_cast<int>(std::log2(new_axi_cities_per_beat));

        int new_hw_cities_per_beat = HW_CITIES_PER_BEAT;
        while (new_hw_cities_per_beat * new_city_bits < new_fitness_bits) {
            new_hw_cities_per_beat *= 2;
        }
        int new_hw_cities_per_beat_log2 = static_cast<int>(std::log2(new_hw_cities_per_beat));
        int new_hw_beat_width = new_city_bits * new_hw_cities_per_beat;
        int new_hw_beats_per_axi_beat = new_axi_beat_width / new_hw_beat_width;
        int new_hw_beats_per_axi_beat_log2 = new_axi_cities_per_beat_log2 - new_hw_cities_per_beat_log2;
        int new_hw_max_city_beats = (new_max_cities + new_hw_cities_per_beat - 1) / new_hw_cities_per_beat;
        int new_hw_max_beats = new_hw_max_city_beats + HW_FITNESS_BEATS;
        int new_hw_max_beats_log2 = static_cast<int>(std::ceil(std::log2(new_hw_max_beats)));

        int new_cache_entry_bits = 2 * new_coord_bits + new_capacity_bits;
        int new_cache_entries_per_beat = new_axi_beat_width / new_cache_entry_bits;
        int new_cache_entries_per_beat_log2 = static_cast<int>(std::floor(std::log2(new_cache_entries_per_beat)));
        int new_max_cache_entries = new_max_cities + 1;

        std::cout << "\n======================================================================\n";
        std::cout << "Suggested ga_encoding_constants.hpp configuration for " << problem.name << ":\n";
        std::cout << "======================================================================\n";
        std::cout << "// 1. Problem Instance Constraints\n";
        std::cout << "#define MAX_CITIES                  " << new_max_cities << "\n";
        std::cout << "#define COORD_BITS                  " << new_coord_bits << "\n";
        std::cout << "#define CAPACITY_BITS               " << new_capacity_bits << "\n\n";
        std::cout << "// 2. Fitness Encoding Constants\n";
        std::cout << "#define FITNESS_BITS                " << new_fitness_bits << "\n\n";
        std::cout << "// 3. City Gene Encoding Constants\n";
        std::cout << "#define NODE_ID_BITS                " << new_node_id_bits << " // ceil(log2(MAX_CITIES))\n";
        std::cout << "#define DEPOT_BITS                   1\n";
        std::cout << "#define DEPOT_FLAG_OFFSET           (NODE_ID_BITS)\n";
        std::cout << "#define CITY_BITS                   " << new_city_bits << " // next power of two of (DEPOT_BITS + NODE_ID_BITS)\n";
        std::cout << "#define CITY_BITS_LOG2               " << new_city_bits_log2 << " // log2(CITY_BITS)\n\n";
        std::cout << "// 4. Host / AXI Interface Beat Constants\n";
        std::cout << "#define AXI_BEAT_WIDTH              " << new_axi_beat_width << "\n";
        std::cout << "#define AXI_BYTES                   (AXI_BEAT_WIDTH / 8) // " << new_axi_bytes << "\n";
        std::cout << "#define AXI_CITIES_PER_BEAT         " << new_axi_cities_per_beat << " // AXI_BEAT_WIDTH / CITY_BITS\n";
        std::cout << "#define AXI_CITIES_PER_BEAT_LOG2     " << new_axi_cities_per_beat_log2 << " // log2(AXI_CITIES_PER_BEAT)\n";
        std::cout << "#define AXI_FITNESS_BEATS            1\n\n";
        std::cout << "// 5. Hardware Pipeline Beat Constants\n";
        std::cout << "#define HW_CITIES_PER_BEAT          " << new_hw_cities_per_beat << "\n";
        std::cout << "#define HW_CITIES_PER_BEAT_LOG2     " << new_hw_cities_per_beat_log2 << "\n";
        std::cout << "#define HW_BEAT_WIDTH               (CITY_BITS * HW_CITIES_PER_BEAT) // " << new_hw_beat_width << "\n";
        std::cout << "#define HW_BEATS_PER_AXI_BEAT       (AXI_BEAT_WIDTH / HW_BEAT_WIDTH) // " << new_hw_beats_per_axi_beat << "\n";
        std::cout << "#define HW_BEATS_PER_AXI_BEAT_LOG2  (AXI_CITIES_PER_BEAT_LOG2 - HW_CITIES_PER_BEAT_LOG2) // " << new_hw_beats_per_axi_beat_log2 << "\n";
        std::cout << "#define HW_MAX_CITY_BEATS           " << new_hw_max_city_beats << "\n";
        std::cout << "#define HW_FITNESS_BEATS            1\n";
        std::cout << "#define HW_MAX_BEATS                " << new_hw_max_beats << "\n";
        std::cout << "#define HW_MAX_BEATS_LOG2           " << new_hw_max_beats_log2 << "\n\n";
        std::cout << "// 6. Node Cache Encoding Constants\n";
        std::cout << "#define NODE_CACHE_ENTRY_BITS        " << new_cache_entry_bits << "\n";
        std::cout << "#define NODE_CACHE_COORD_X_OFFSET     0\n";
        std::cout << "#define NODE_CACHE_COORD_Y_OFFSET    (COORD_BITS)\n";
        std::cout << "#define NODE_CACHE_DEMAND_OFFSET     (2 * COORD_BITS)\n";
        std::cout << "#define NODE_CACHE_ENTRIES_PER_BEAT      " << new_cache_entries_per_beat << "\n";
        std::cout << "#define NODE_CACHE_ENTRIES_PER_BEAT_LOG2 " << new_cache_entries_per_beat_log2 << "\n";
        std::cout << "#define MAX_CACHE_ENTRIES            " << new_max_cache_entries << " // MAX_CITIES + 1\n";
        std::cout << "======================================================================\n\n";

        if (throw_on_error) {
            throw std::runtime_error("Problem instance is not valid.");
        }
        return false;
    }

    return true;
}
