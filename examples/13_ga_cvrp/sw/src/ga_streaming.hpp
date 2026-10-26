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
 * Common configuration of the CVRP GA data path, shared between the
 * host-side codec (population_codec.hpp), the remaining host code
 * (main.cpp) and any other consumer. These values must match the
 * hardware datapath (see hw/src/hls/processing_node).
 *
 * The project is compiled as C++17, so the idiomatic way to expose
 * compile-time constants across translation units is a plain header
 * with inline constexpr variables (no #define / .cpp definitions).
 */

#ifndef GA_STREAMING_HPP
#define GA_STREAMING_HPP

#include <cstddef>
#include <cstdint>
#include <vector>

#include "ga_encoding_constants.hpp"
#include "ga.hpp"


std::vector<uint8_t> encode_node_cache(
    const ProblemInstance &problem
);

std::vector<uint8_t> encode_population_fixed(
    const ProblemInstance &problem,
    const std::vector<Individual> &population
);

Individual decode_individual_fixed(
    const ProblemInstance &problem,
    const std::uint8_t *beat_bytes
);

std::vector<Individual> decode_population_fixed(
    const ProblemInstance &problem,
    const std::uint8_t *buffer,
    std::size_t num_individuals
);

void population_from_buffer(
    const std::uint8_t *buffer,
    std::size_t num_individuals,
    std::vector<EncodedIndividual> &population,
    int problem_dimension,
    std::size_t pop_offset = 0
);

void population_to_buffer(std::vector<EncodedIndividual> &population, std::uint8_t* bytes, int problem_dimension, bool reversedOrder=false);


#endif
