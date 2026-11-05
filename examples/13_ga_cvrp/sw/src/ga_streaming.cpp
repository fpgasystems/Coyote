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

#include <array>
#include <cstring>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>

#include "ga_streaming.hpp"
#include "ga.hpp"


std::vector<uint8_t> encode_node_cache(const ProblemInstance &problem) {
    const int num_cities = static_cast<int>(problem.nodes.size());
    const int total_beats = get_total_cache_beats(num_cities);
    std::vector<uint8_t> buffer(total_beats * AXI_BYTES, 0);

    const uint64_t coord_mask = (1ULL << COORD_BITS) - 1ULL;
    const uint64_t demand_mask = (1ULL << CAPACITY_BITS) - 1ULL;

    auto encode_entry = [&](int idx, uint64_t x_val, uint64_t y_val, uint64_t demand_val) {
        int beat_idx = idx >> NODE_CACHE_ENTRIES_PER_BEAT_LOG2;
        int word_idx = idx & (NODE_CACHE_ENTRIES_PER_BEAT - 1);

        uint64_t *words = reinterpret_cast<uint64_t *>(buffer.data() + beat_idx * AXI_BYTES);
        uint64_t x = x_val & coord_mask;
        uint64_t y = y_val & coord_mask;
        uint64_t demand = demand_val & demand_mask;

        words[word_idx] = (x << NODE_CACHE_COORD_X_OFFSET) |
                          (y << NODE_CACHE_COORD_Y_OFFSET) |
                          (demand << NODE_CACHE_DEMAND_OFFSET);
    };

    for (int i = 0; i < num_cities; ++i) {
        const ProblemNode &node = problem.nodes[i];
        encode_entry(i, node.x, node.y, node.demand);
    }

    // Depot coordinates stored at index num_cities
    encode_entry(num_cities, problem.depot.x, problem.depot.y, 0);

    return buffer;
}

std::vector<std::array<uint64_t, 8>> encode_individual_fixed(
    const ProblemInstance &problem,
    const Individual &individual
) {
    const int num_cities = static_cast<int>(problem.nodes.size());
    const int total_city_beats = get_total_axi_city_beats(num_cities);
    const int beats_per_individual = get_total_axi_beats(num_cities);

    std::vector<std::array<uint64_t, 8>> beats(beats_per_individual);
    for (auto &beat : beats) {
        beat.fill(0);
    }

    const uint64_t id_mask = (1ULL << NODE_ID_BITS) - 1ULL;

    for (size_t i = 0; i < individual.tour.size(); ++i) {
        const auto &gene = individual.tour[i];
        uint64_t id_val    = static_cast<uint64_t>(gene.node_id) & id_mask;
        uint64_t depot_val = gene.depot_after ? 1ULL : 0ULL;
        uint64_t city      = id_val | (depot_val << DEPOT_FLAG_OFFSET);

        size_t beat_idx = i / AXI_CITIES_PER_BEAT;
        size_t slot = i % AXI_CITIES_PER_BEAT;
        size_t bit_offset = slot * CITY_BITS;

        beats[beat_idx][bit_offset / 64] |= (city << (bit_offset % 64));
    }

    // Trailing beat: only contains fitness in lower FITNESS_BITS bits
    beats[total_city_beats][0] = static_cast<uint64_t>(individual.fitness);

    return beats;
}

std::vector<uint8_t> encode_population_fixed(
    const ProblemInstance &problem,
    const std::vector<Individual> &population
) {
    const int beats_per_individual = get_total_axi_beats(static_cast<int>(problem.nodes.size()));

    std::vector<uint8_t> buffer;
    buffer.reserve(population.size() * beats_per_individual * AXI_BYTES);
    for (const auto &ind : population) {
        auto beats = encode_individual_fixed(problem, ind);
        for (const auto &beat : beats) {
            const uint8_t *bytes = reinterpret_cast<const uint8_t *>(beat.data());
            buffer.insert(buffer.end(), bytes, bytes + AXI_BYTES);
        }
    }
    return buffer;
}

Individual decode_individual_fixed(
    const ProblemInstance &problem,
    const std::uint8_t *beat_bytes
) {
    const int num_cities = static_cast<int>(problem.nodes.size());
    const int total_city_beats = get_total_axi_city_beats(num_cities);

    Individual individual;
    individual.tour.reserve(num_cities);

    const uint64_t id_mask = (1ULL << NODE_ID_BITS) - 1ULL;
    const uint64_t city_mask = (CITY_BITS >= 64) ? ~0ULL : ((1ULL << CITY_BITS) - 1ULL);

    for (int i = 0; i < num_cities; ++i) {
        int beat_idx = i / AXI_CITIES_PER_BEAT;
        int slot = i % AXI_CITIES_PER_BEAT;
        int bit_offset = slot * CITY_BITS;

        const uint64_t *words = reinterpret_cast<const uint64_t *>(
            beat_bytes + (beat_idx * AXI_BYTES)
        );

        uint64_t city = (words[bit_offset / 64] >> (bit_offset % 64)) & city_mask;
        int node_id = static_cast<int>(city & id_mask);
        bool depot_after = ((city >> DEPOT_FLAG_OFFSET) & 1ULL) != 0ULL;

        if (node_id >= 0 && node_id < num_cities) {
            individual.tour.push_back(TourGene{node_id, depot_after});
        } else {
            throw std::runtime_error("Decoded node_id is out of range.");
        }
    }

    uint32_t fitness = 0;
    std::memcpy(&fitness, beat_bytes + total_city_beats * AXI_BYTES, sizeof(fitness));
    individual.fitness = fitness;

    return individual;
}

std::vector<Individual> decode_population_fixed(
    const ProblemInstance &problem,
    const std::uint8_t *buffer,
    std::size_t num_individuals
) {
    const int beats_per_individual = get_total_axi_beats(static_cast<int>(problem.nodes.size()));

    std::vector<Individual> population;
    population.reserve(num_individuals);

    const std::size_t bytes_per_individual = beats_per_individual * AXI_BYTES;

    for (std::size_t i = 0; i < num_individuals; ++i) {
        const std::uint8_t *ind_bytes = buffer + (i * bytes_per_individual);
        population.push_back(decode_individual_fixed(problem, ind_bytes));
    }

    return population;
}

void population_from_buffer(
    const std::uint8_t *buffer,
    std::size_t num_individuals,
    std::vector<EncodedIndividual> &population,
    int problem_dimension,
    std::size_t pop_offset
) {
    const int num_cities = problem_dimension - 1;
    const int total_city_beats = get_total_axi_city_beats(num_cities);
    const int beats_per_individual = get_total_axi_beats(num_cities);
    const std::size_t bytes_per_individual = beats_per_individual * AXI_BYTES;
    const std::size_t city_bytes = (num_cities * CITY_BITS) / 8;
    const std::size_t fitness_offset = total_city_beats * AXI_BYTES;

    for (std::size_t i = 0; i < num_individuals; ++i) {
        const std::uint8_t *ind_bytes = buffer + (i * bytes_per_individual);
        uint32_t raw_fitness = 0;
        std::memcpy(&raw_fitness, ind_bytes + fitness_offset, sizeof(raw_fitness));
        population[pop_offset + i].fitness = raw_fitness;
        population[pop_offset + i].bytes = ind_bytes;
        population[pop_offset + i].hash = hash_genome(ind_bytes, city_bytes);
    }
}

void population_to_buffer(std::vector<EncodedIndividual> &population, std::uint8_t* bytes, int problem_dimension, bool reversedOrder) {
    const int beats_per_individual = get_total_axi_beats(problem_dimension - 1);
    if (reversedOrder) {
        for (int i=population.size()-1; i>=0; --i) {
            std::uint8_t *dest = bytes + (i * beats_per_individual * AXI_BYTES);
            std::memcpy(dest, population[i].bytes, beats_per_individual * AXI_BYTES);
            population[i] = EncodedIndividual{dest, population[i].fitness, population[i].hash};
        }
    } else {
        for (int i=0; i<population.size(); ++i) {
            std::memcpy(bytes, population[i].bytes, beats_per_individual * AXI_BYTES);
            population[i] = EncodedIndividual{bytes, population[i].fitness, population[i].hash};
            bytes += beats_per_individual * AXI_BYTES;
        }
    }
}