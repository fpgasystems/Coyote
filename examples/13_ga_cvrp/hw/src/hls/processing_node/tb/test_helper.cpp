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

#include "test_helper.hpp"
#include "ga.hpp"

#include <cstring>
#include <algorithm>

void tb_push_bytes(hls::stream<axi_word_t> &stream,
                   const std::uint8_t *bytes,
                   std::size_t n_bytes,
                   bool is_last) {
    constexpr std::size_t beat_bytes_count = AXI_BYTES;          // bytes per beat (e.g., 64)
    constexpr std::size_t beat_words = AXI_BYTES / sizeof(uint64_t); // number of 64-bit words (8)
    const std::size_t total_beats = (n_bytes + beat_bytes_count - 1) / beat_bytes_count;

    for (std::size_t b = 0; b < total_beats; b++) {
        axi_word_t word;
        word.data = 0;
        word.keep = -1;
        word.strb = -1;
        word.last = (is_last && b + 1 == total_beats) ? 1 : 0;

        for (std::size_t w = 0; w < beat_words; ++w) {
            std::uint64_t chunk = 0;
            std::size_t offset = b * beat_bytes_count + w * sizeof(uint64_t);
            if (offset < n_bytes) {
                std::size_t remaining = n_bytes - offset;
                std::memcpy(&chunk, bytes + offset,
                            std::min(sizeof(chunk), remaining));
            }
            word.data.range((w + 1) * 64 - 1, w * 64) = chunk;
        }
        stream.write(word);
    }
}

void tb_pull_bytes(hls::stream<axi_word_t> &stream,
                   std::uint8_t *bytes,
                   std::size_t n_bytes) {
    constexpr std::size_t beat_bytes_count = AXI_BYTES;
    constexpr std::size_t beat_words = AXI_BYTES / sizeof(uint64_t);
    const std::size_t total_beats = (n_bytes + beat_bytes_count - 1) / beat_bytes_count;

    for (std::size_t b = 0; b < total_beats; b++) {
        axi_word_t word = stream.read();
        for (std::size_t w = 0; w < beat_words; ++w) {
            std::uint64_t chunk = word.data.range((w + 1) * 64 - 1, w * 64);
            std::size_t offset = b * beat_bytes_count + w * sizeof(uint64_t);
            if (offset < n_bytes) {
                std::size_t remaining = n_bytes - offset;
                std::memcpy(bytes + offset, &chunk,
                            std::min(sizeof(chunk), remaining));
            }
        }
    }
}

void make_individual_beats(const ProblemInstance &problem, const Individual &individual, IndividualAsBeats &out) {
    const int num_cities = static_cast<int>(individual.tour.size());
    const int total_beats = get_total_beats(num_cities);
    for (int b = 0; b < total_beats; ++b) {
        out[b] = 0;
    }

    for (std::size_t i = 0; i < individual.tour.size(); ++i) {
        const auto &gene = individual.tour[i];

        City city = 0;
        set_is_depot(city, gene.depot_after);
        set_node_id(city, gene.node_id);

        set_city(out, static_cast<int>(i), city);
    }

    set_fitness(out, Fitness(individual.fitness), num_cities);
}

Individual decode_individual(const ProblemInstance &problem, const IndividualAsBeats &ind, int num_cities) {   
    Individual individual;
    individual.fitness = static_cast<uint32_t>(get_fitness(ind, num_cities));

    for (int i = 0; i < num_cities; ++i) {
        City city = get_city(ind, i);
        int node_id = static_cast<int>(get_node_id(city));
        bool depot_after = get_is_depot(city);
        individual.tour.push_back(TourGene{node_id, depot_after});
    }

    return individual;
}

void tb_push_individuals(hls::stream_of_blocks<IndividualAsBeats> &stream, const ProblemInstance &problem, const std::vector<Individual> &individuals){
    for (const auto &individual : individuals) {
        hls::write_lock<IndividualAsBeats> ind(stream);
        make_individual_beats(problem, individual, ind);
    }
}

std::vector<Individual> tb_pull_individuals(hls::stream_of_blocks<IndividualAsBeats> &stream, const ProblemInstance &problem, int population_size){
    std::vector<Individual> individuals;
    for (int i = 0; i < population_size; ++i) {
        hls::read_lock<IndividualAsBeats> ind(stream);
        individuals.push_back(decode_individual(problem, ind, problem.nodes.size()));
    }
    return individuals;
}

std::vector<Individual> build_population(const ProblemInstance &problem,
                                         const std::vector<std::vector<int>> &tours) {
    std::vector<Individual> out;
    for (const std::vector<int> &tour : tours) {
        out.push_back(build_individual(problem, tour));
    }
    return out;
}

std::vector<Individual> build_population(const ProblemInstance &problem,
                                         const std::vector<std::vector<int>> &tours,
                                         std::uint32_t fitness_base) {
    std::vector<Individual> out(tours.size());
    for (std::size_t i = 0; i < tours.size(); ++i) {
        out[i].fitness = fitness_base + static_cast<std::uint32_t>(i);
        out[i].tour.reserve(tours[i].size());
        for (int node_id : tours[i]) {            
            out[i].tour.push_back(TourGene{node_id, false});
        }
    }
    return out;
}
