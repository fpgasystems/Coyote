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
 * Parser for CVRP problem instance files (TSPLIB-like .vrp format).
 * Pure host code, no Coyote dependency.
 */

#ifndef CVRP_PROBLEM_PARSER_HPP
#define CVRP_PROBLEM_PARSER_HPP

#include <string>

#include "ga.hpp"

/*
 * Calculate the highest possible coordinate precision factor for a given coordinate span
 * and problem dimension such that coordinates fit in COORD_BITS and maximum fitness fits
 * in FITNESS_BITS.
 */
int calculate_highest_precision(double span_x, double span_y, int dimension);

/*
 * Parse a CVRP instance file. Coordinates are scaled by precision (to allow higher
 * precision in sqrt distance calculations) and normalized by subtracting the minimum
 * x / y so that they fit into the COORD_BITS-wide encoding fields.
 * If precision is <= 0 (the default), it is automatically set to the highest
 * possible value that fits within COORD_BITS and FITNESS_BITS.
 */
ProblemInstance parse_vrp(const std::string &path, int precision = 0);


#endif
