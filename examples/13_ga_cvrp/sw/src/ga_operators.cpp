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

#include "ga_operators.hpp"

#include <algorithm>
#include <iostream>
#include <limits>
#include <random>

void create_parent_pairs(
    const std::vector<EncodedIndividual> &population,
    std::vector<EncodedIndividual> &parents1,
    std::vector<EncodedIndividual> &parents2,
    std::uint32_t seed
) {
    std::mt19937 gen(seed);
    std::uniform_int_distribution<std::size_t> dist(0, population.size() - 1);

    const std::size_t n_pairs = std::min(parents1.size(), parents2.size());
    for (std::size_t i = 0; i < n_pairs; ++i) {
        std::size_t idx1 = dist(gen);
        std::size_t idx2 = dist(gen);
        std::size_t idx3 = dist(gen);
        std::size_t idx4 = dist(gen);

        parents1[i] = population[idx1].fitness < population[idx2].fitness ? population[idx1] : population[idx2];
        parents2[i] = population[idx3].fitness < population[idx4].fitness ? population[idx3] : population[idx4];
    }
}

void update_generation_with_parents(
    std::vector<EncodedIndividual> &offspring,
    const std::vector<EncodedIndividual> &parents1,
    const std::vector<EncodedIndividual> &parents2
) {
    const std::size_t n = std::min(parents1.size(), parents2.size());
    for (std::size_t j = 0; j < n; ++j) {
        if (offspring[j].fitness >= parents1[j].fitness) {
            offspring[j] = parents1[j];
        }
        if (offspring[n + j].fitness >= parents2[j].fitness) {
            offspring[n + j] = parents2[j];
        }
    }
}

void update_population(
    std::vector<EncodedIndividual> &population,
    std::vector<EncodedIndividual> &new_generation,
    std::vector<EncodedIndividual> &new_population,
    int n_keep_best
) {
    std::sort(new_generation.begin(), new_generation.end());

    int i_pop = 0;
    int i_new = 0;
    EncodedIndividual last_ind = {nullptr, std::numeric_limits<std::uint32_t>::max(), std::numeric_limits<std::uint64_t>::max()};
    int i_new_pop = 0;

    while (i_new_pop < n_keep_best && (i_new < new_generation.size() || i_pop < population.size())) {
        if (i_new < new_generation.size() && i_pop < population.size()) {
            // If both individuals are equal (same fitness and hash), we prefer the new generation individual
            if (new_generation[i_new] == population[i_pop]) {
                new_population[i_new_pop] = new_generation[i_new];
                last_ind = new_generation[i_new];
                while (++i_new < new_generation.size() && new_generation[i_new] == last_ind);
                i_pop++;
                i_new_pop++;
            } else if (new_generation[i_new] < population[i_pop]) {
                new_population[i_new_pop] = new_generation[i_new];
                last_ind = new_generation[i_new];
                while (++i_new < new_generation.size() && new_generation[i_new] == last_ind);
                i_new_pop++;
            } else {
                new_population[i_new_pop] = population[i_pop];
                last_ind = population[i_pop];
                while (++i_pop < population.size() && population[i_pop] == last_ind);
                i_new_pop++;
            }
        } else if (i_new < new_generation.size()) {
            new_population[i_new_pop] = new_generation[i_new];
            last_ind = new_generation[i_new];
            while (++i_new < new_generation.size() && new_generation[i_new] == last_ind);
            i_new_pop++;
        } else {
            new_population[i_new_pop] = population[i_pop];
            last_ind = population[i_pop];
            while (++i_pop < population.size() && population[i_pop] == last_ind);
            i_new_pop++;
        }
    }

    // Fill the rest of the new population with individuals from the new generation eliminating duplicates
    int n_keep_actual = i_new_pop;
    for (int i = i_new; i < new_generation.size() && i_new_pop < population.size(); i++) {
        if (new_generation[i] == last_ind) {
            continue;
        }

        new_population[i_new_pop] = new_generation[i];
        i_new_pop++;
        last_ind = new_generation[i];
    }
    
    // Fill the rest of the new population with individuals from the old population eliminating duplicates
    int new_pop_ge_index = n_keep_actual;
    for (int i = i_pop; i < population.size() && i_new_pop < population.size(); i++) {
        while (new_pop_ge_index < i_new_pop && new_population[new_pop_ge_index] < population[i]) {
            new_pop_ge_index++;
        }

        // if not equal then new_pop must be greater thus pop[i] does not yet exist
        if (new_pop_ge_index >= i_new_pop || new_population[new_pop_ge_index] != population[i]) {
            new_population[i_new_pop] = population[i];
            i_new_pop++;
        }
    }

    if (i_new_pop < population.size()) {
        std::cerr << "Warning: Only "
                  << i_new_pop << " individuals were available for population size "
                  << population.size() << ". Filling remaining "
                  << (population.size() - i_new_pop) << " slots." << std::endl;
        while (i_new_pop < population.size()) {
            new_population[i_new_pop] = new_population[0];
            i_new_pop++;
        }
    }

    std::sort(new_population.begin(), new_population.end());
}
