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

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Standalone encode/decode roundtrip test for the CVRP population codec.
 *
 * Reads the 16-node P-n16-k8 problem instance, generates a small population
 * of two individuals, encodes the population into the 512-bit beat layout,
 * prints the bytes with field-boundary markers, decodes the buffer again
 * and checks that the decoded individuals match the originals.
 *
 *
 * Build (standalone, no Coyote dependency):
 *   g++ -std=c++17 -I . test_encode_decode.cpp \
       ga.cpp ga_streaming.cpp problem_parser.cpp -o test_encode_decode && ./test_encode_decode
 */

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <cmath>

#include "ga.hpp"
#include "ga_streaming.hpp"
#include "problem_parser.hpp"

namespace {

void print_hex_dump(const std::string &label, const std::uint8_t *bytes, std::size_t size) {
    std::cout << label << " (" << size << " B):\n";
    for (std::size_t i = 0; i < size; i += 16) {
        std::printf("  %04zx: ", i);
        for (std::size_t j = 0; j < 16; ++j) {
            if (i + j < size) {
                std::printf("%02x ", bytes[i + j]);
            } else {
                std::printf("   ");
            }
        }
        std::printf("\n");
    }
}

void print_beat_markers(const std::string &label, const std::uint8_t *beat_bytes) {
    std::cout << label << " bit layout (Memory Stream Order LSB->MSB, '|' city/field, '-' sub-field):\n  ";

    for (int abs_bit = 0; abs_bit < AXI_BEAT_WIDTH; ++abs_bit) {
        // Sample bits LSB-first within each byte
        int byte_idx = abs_bit / 8;
        int bit_in_byte = abs_bit % 8;

        bool set = (beat_bytes[byte_idx] >> bit_in_byte) & 1;
        std::printf("%c", set ? '1' : '0');

        int city_idx = abs_bit / CITY_BITS;
        int bit_in_city = abs_bit % CITY_BITS;

        // Print dividers (except after the very last bit of the AXI beat)
        if (abs_bit + 1 < AXI_BEAT_WIDTH) {
            // End of city boundary (|)
            if (bit_in_city == CITY_BITS - 1) {
                std::printf("|");
            } 
            // Sub-field boundaries inside city (-)
            else {
                if (bit_in_city == NODE_ID_BITS - 1 || 
                    bit_in_city == DEPOT_FLAG_OFFSET) {
                    std::printf("-");
                }
            }

            // New line formatting at city boundaries for readability
            if (bit_in_city == CITY_BITS - 1 && (city_idx + 1) % 8 == 0) {
                std::printf("\n  ");
            }
        }
    }
    std::printf("\n");
}

void print_decoded_fields(const std::string &label, Individual& individual, const ProblemInstance &problem) {
    std::cout << label << " decoded tour & fitness:\n";

    for(std::size_t i = 0; i < individual.tour.size(); ++i) {
        const auto &city = individual.tour[i];
        std::printf("  city %2zu [beat %zu, slot %2zu] depot_after=%u node_id=%d\n",
                    i, i / AXI_CITIES_PER_BEAT, i % AXI_CITIES_PER_BEAT, city.depot_after, city.node_id);
    }

    std::size_t total_city_beats = get_total_axi_city_beats(individual.tour.size());
    std::printf("  fitness beat %zu [bits 0..%d] fitness=%u\n",
                total_city_beats, FITNESS_BITS - 1, individual.fitness);
}

bool test_encode_decode(const ProblemInstance &problem) {
    const std::size_t population_size = 2;
    const std::vector<Individual> population = build_initial_population(problem, population_size, 0xC0FFEEu);

    for (std::size_t i = 0; i < population.size(); ++i) {
        std::cout << "Individual " << i << ": " << population[i] << "\n";
    }
    std::cout << "\n";

    const std::vector<std::uint8_t> encoded = encode_population_fixed(problem, population);
    std::vector<Individual> decoded = decode_population_fixed(problem, encoded.data(), population.size());
    const int beats_per_individual = get_total_axi_beats(problem.dimension - 1);
    const std::size_t bytes_per_individual = beats_per_individual * AXI_BYTES;

    for (std::size_t i = 0; i < population.size(); ++i) {
        const std::uint8_t *bytes = encoded.data() + i * bytes_per_individual;
        print_hex_dump("Individual " + std::to_string(i), bytes, bytes_per_individual);
        for (int b = 0; b < beats_per_individual; ++b) {
            std::string beat_label = "Individual " + std::to_string(i) + " Beat " + std::to_string(b);
            if (b == beats_per_individual - 1) beat_label += " (Fitness Beat)";
            else beat_label += " (City Beat)";
            print_beat_markers(beat_label, bytes + b * AXI_BYTES);
        }
        print_decoded_fields("Individual " + std::to_string(i), decoded[i], problem);
        std::cout << "\n";
    }

    bool ok = decoded.size() == population.size();
    for (std::size_t i = 0; ok && i < population.size(); ++i) {
        if (decoded[i] != population[i]) {
            std::cerr << "Mismatch at individual " << i << ":\n"
                      << "  original: " << population[i] << "\n"
                      << "  decoded:  " << decoded[i] << "\n";
            ok = false;
        }
    }

    if (ok) {
        std::cout << "PASS: encode/decode round-trip matches for " << population.size() << " individuals.\n";
        return true;
    } else {
        std::cout << "FAIL: round-trip mismatch.\n";
        return false;
    }
}


bool test_node_cache_encode(const ProblemInstance &problem) {
    std::vector<uint8_t> cache = encode_node_cache(problem);
    const uint64_t coord_mask = (1ULL << COORD_BITS) - 1ULL;
    const uint64_t demand_mask = (1ULL << CAPACITY_BITS) - 1ULL;

    auto check_entry = [&](int idx, uint64_t exp_x, uint64_t exp_y, uint64_t exp_demand, const std::string &label) {
        int beat_idx = idx >> NODE_CACHE_ENTRIES_PER_BEAT_LOG2;
        int word_idx = idx & (NODE_CACHE_ENTRIES_PER_BEAT - 1);
        const uint64_t *words = reinterpret_cast<const uint64_t *>(cache.data() + beat_idx * AXI_BYTES);
        uint64_t val = words[word_idx];
        uint64_t x = (val >> NODE_CACHE_COORD_X_OFFSET) & coord_mask;
        uint64_t y = (val >> NODE_CACHE_COORD_Y_OFFSET) & coord_mask;
        uint64_t demand = (val >> NODE_CACHE_DEMAND_OFFSET) & demand_mask;
        if (x != (exp_x & coord_mask) || y != (exp_y & coord_mask) || demand != (exp_demand & demand_mask)) {
            std::cerr << "Mismatch in node cache at " << label << " (index " << idx << ")\n";
            return false;
        }
        return true;
    };

    for (std::size_t i = 0; i < problem.nodes.size(); ++i) {
        if (!check_entry(static_cast<int>(i), problem.nodes[i].x, problem.nodes[i].y, problem.nodes[i].demand, "node " + std::to_string(i))) {
            return false;
        }
    }

    // Verify depot entry at index problem.nodes.size()
    int depot_idx = static_cast<int>(problem.nodes.size());
    if (!check_entry(depot_idx, problem.depot.x, problem.depot.y, 0, "depot")) {
        return false;
    }

    std::cout << "PASS: encode_node_cache verified for " << problem.nodes.size() << " nodes + depot.\n";
    return true;
}

} // namespace

#include <fstream>

static std::string find_vrp_file(const std::string &arg_path) {
    if (!arg_path.empty()) {
        std::ifstream test_f(arg_path);
        if (test_f.good()) return arg_path;
    }
    const std::vector<std::string> candidates = {
        "problem_instances/P-n40-k5.vrp",
        "../problem_instances/P-n40-k5.vrp",
        "../../problem_instances/P-n40-k5.vrp"
    };
    for (const auto &c : candidates) {
        std::ifstream f(c);
        if (f.good()) return c;
    }
    return arg_path.empty() ? "problem_instances/P-n40-k5.vrp" : arg_path;
}

int main(int argc, char *argv[]) {
    const std::string vrp_file = find_vrp_file((argc > 1) ? argv[1] : "");

    try {
        const ProblemInstance problem = parse_vrp(vrp_file);
        std::cout << "Loaded problem: " << problem.name
                  << "  dimension=" << problem.dimension
                  << "  capacity=" << problem.capacity
                  << "  customers=" << numCustomers(problem) << "\n\n";

        if (!test_node_cache_encode(problem)) {
            return EXIT_FAILURE;
        }

        if (!test_encode_decode(problem)) {
            return EXIT_FAILURE;
        }

        return EXIT_SUCCESS;
    } catch (const std::exception &e) {
        std::cerr << "FAIL: " << e.what() << "\n";
        return EXIT_FAILURE;
    }
}
