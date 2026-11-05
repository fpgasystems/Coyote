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

#ifndef TEST_HELPER_HPP
#define TEST_HELPER_HPP

#include "types.hpp"
#include "ga.hpp"

#include <cstddef>
#include <cstdint>
#include <hls_streamofblocks.h>

void tb_push_bytes(hls::stream<axi_word_t> &stream,
                   const std::uint8_t *bytes,
                   std::size_t n_bytes,
                   bool is_last);

void tb_pull_bytes(hls::stream<axi_word_t> &stream,
                   std::uint8_t *bytes,
                   std::size_t n_bytes);

void tb_push_individuals(hls::stream_of_blocks<IndividualAsBeats> &stream, const ProblemInstance &problem, const std::vector<Individual> &individuals);

std::vector<Individual> tb_pull_individuals(hls::stream_of_blocks<IndividualAsBeats> &stream, const ProblemInstance &problem, int population_size);

std::vector<Individual> build_population(const ProblemInstance &problem,
                                         const std::vector<std::vector<int>> &tours);

std::vector<Individual> build_population(const ProblemInstance &problem,
                                         const std::vector<std::vector<int>> &tours,
                                         std::uint32_t fitness_base);

#endif // TEST_HELPER_HPP
