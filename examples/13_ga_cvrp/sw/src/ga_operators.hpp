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

#ifndef GA_OPERATORS_HPP
#define GA_OPERATORS_HPP

#include <cstdint>
#include <vector>
#include "batch_job.hpp"

/*
 * Tournament selection creating two parent streams for crossover.
 */
void create_parent_pairs(
    const std::vector<EncodedIndividual> &population,
    std::vector<EncodedIndividual> &parents1,
    std::vector<EncodedIndividual> &parents2,
    std::uint32_t seed
);

/*
 * Updates offspring in-place using parent fallback: a child is admitted into the new generation
 * only if its fitness is strictly better than the parent in the parents array with the same index
 * (stream 0 vs 1). Otherwise, the parent is retained in its place.
 */
void update_generation_with_parents(
    std::vector<EncodedIndividual> &offspring,
    const std::vector<EncodedIndividual> &parents1,
    const std::vector<EncodedIndividual> &parents2
);

/*
 * Update the population with the new generation, keeping the best n_keep_best individuals over both generations.
 * The new generation is sorted by fitness in ascending order (lower fitness is better).
 * Duplicate individuals (matching fitness and genome hash) are eliminated.
 */
void update_population(
    std::vector<EncodedIndividual> &population,
    std::vector<EncodedIndividual> &new_generation,
    std::vector<EncodedIndividual> &new_population,
    int n_keep_best
);

#endif // GA_OPERATORS_HPP
