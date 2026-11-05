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

#include "problem_parser.hpp"
#include "ga_encoding_constants.hpp"

#include <algorithm>
#include <fstream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <utility>
#include <cmath>


std::string trim(const std::string &text) {
    const auto first = text.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = text.find_last_not_of(" \t\r\n");
    return text.substr(first, last - first + 1);
}

std::string value_after_colon(const std::string &line) {
    const auto colon = line.find(':');
    if (colon == std::string::npos) {
        return trim(line);
    }
    return trim(line.substr(colon + 1));
}

int calculate_highest_precision(double span_x, double span_y, int dimension) {
    constexpr uint64_t max_coord = (1ULL << COORD_BITS) - 1ULL;
    constexpr uint64_t max_fitness = (1ULL << FITNESS_BITS) - 1ULL;

    double max_span = std::max(span_x, span_y);
    if (max_span <= 0.0) {
        return static_cast<int>(max_coord);
    }

    double p_coord = static_cast<double>(max_coord) / max_span;

    int num_cities = dimension - 1;
    double p_fitness = p_coord;
    if (num_cities > 0) {
        double diag = std::sqrt(span_x * span_x + span_y * span_y);
        if (diag > 0.0) {
            double max_diag = static_cast<double>(max_fitness / (2ULL * static_cast<uint64_t>(num_cities)));
            p_fitness = max_diag / diag;
        }
    }

    int precision = static_cast<int>(std::floor(std::min(p_coord, p_fitness)));
    return std::max(1, precision);
}

ProblemInstance parse_vrp(const std::string &path, int precision) {
    if (precision < 0) {
        throw std::invalid_argument("precision must not be negative");
    }
    std::ifstream input(path);
    if (!input.is_open()) {
        throw std::runtime_error("Could not open VRP file: " + path);
    }

    ProblemInstance problem;
    struct RawCoord {
        int id = 0;
        double x = 0.0;
        double y = 0.0;
        int demand = 0;
    };
    std::vector<RawCoord> raw_nodes;
    int expected_dimension = -1;
    int depot_id = -1;

    enum class Section {
        Header,
        NodeCoords,
        Demands,
        Depot
    } section = Section::Header;

    std::string line;
    while (std::getline(input, line)) {
        line = trim(line);
        if (line.empty()) {
            continue;
        }

        if (line == "NODE_COORD_SECTION") {
            section = Section::NodeCoords;
            continue;
        }
        if (line == "DEMAND_SECTION") {
            section = Section::Demands;
            continue;
        }
        if (line == "DEPOT_SECTION") {
            section = Section::Depot;
            continue;
        }
        if (line == "EOF") {
            break;
        }

        if (section == Section::Header) {
            if (line.rfind("NAME", 0) == 0) {
                problem.name = value_after_colon(line);
            } else if (line.rfind("DIMENSION", 0) == 0) {
                expected_dimension = std::stoi(value_after_colon(line));
                raw_nodes.resize(static_cast<std::size_t>(expected_dimension) + 1);
            } else if (line.rfind("CAPACITY", 0) == 0) {
                problem.capacity = std::stoi(value_after_colon(line));
            }
            continue;
        }

        if (section == Section::NodeCoords) {
            std::istringstream iss(line);
            int id;
            double x;
            double y;
            if (!(iss >> id >> x >> y)) {
                throw std::runtime_error("Failed to parse NODE_COORD_SECTION line: " + line);
            }
            if (raw_nodes.empty()) {
                throw std::runtime_error("DIMENSION must appear before NODE_COORD_SECTION");
            }
            raw_nodes.at(static_cast<std::size_t>(id)).id = id;
            raw_nodes.at(static_cast<std::size_t>(id)).x = x;
            raw_nodes.at(static_cast<std::size_t>(id)).y = y;
            continue;
        }

        if (section == Section::Demands) {
            std::istringstream iss(line);
            int id = 0;
            int demand = 0;
            if (!(iss >> id >> demand)) {
                throw std::runtime_error("Failed to parse DEMAND_SECTION line: " + line);
            }
            if (raw_nodes.empty()) {
                throw std::runtime_error("DIMENSION must appear before DEMAND_SECTION");
            }
            raw_nodes.at(static_cast<std::size_t>(id)).demand = demand;
            continue;
        }

        if (section == Section::Depot) {
            int value = 0;
            std::istringstream iss(line);
            if (!(iss >> value)) {
                throw std::runtime_error("Failed to parse DEPOT_SECTION line: " + line);
            }
            if (value == -1) {
                section = Section::Header;
                continue;
            }
            depot_id = value;
            continue;
        }
    }

    if (expected_dimension <= 0 || raw_nodes.size() != static_cast<std::size_t>(expected_dimension) + 1) {
        throw std::runtime_error("VRP file did not provide a valid DIMENSION");
    }
    if (problem.capacity <= 0) {
        throw std::runtime_error("VRP file did not provide a valid CAPACITY");
    }
    if (depot_id <= 0 || depot_id > expected_dimension) {
        throw std::runtime_error("VRP file did not provide a valid depot ID");
    }

    problem.dimension = expected_dimension;

    // Normalize coordinates by subtracting minimum x / y (including depot)
    double min_x = std::numeric_limits<double>::infinity();
    double max_x = -std::numeric_limits<double>::infinity();
    double min_y = std::numeric_limits<double>::infinity();
    double max_y = -std::numeric_limits<double>::infinity();
    for (int id = 1; id <= problem.dimension; ++id) {
        min_x = std::min(min_x, raw_nodes.at(static_cast<std::size_t>(id)).x);
        max_x = std::max(max_x, raw_nodes.at(static_cast<std::size_t>(id)).x);
        min_y = std::min(min_y, raw_nodes.at(static_cast<std::size_t>(id)).y);
        max_y = std::max(max_y, raw_nodes.at(static_cast<std::size_t>(id)).y);
    }

    double span_x = max_x - min_x;
    double span_y = max_y - min_y;

    if (precision <= 0) {
        precision = calculate_highest_precision(span_x, span_y, problem.dimension);
    }
    problem.scaling = precision;

    std::vector<ProblemNode> all_nodes(static_cast<std::size_t>(problem.dimension) + 1);
    for (int id = 1; id <= problem.dimension; ++id) {
        int scaled_x = static_cast<int>(std::round((raw_nodes.at(static_cast<std::size_t>(id)).x - min_x) * precision));
        int scaled_y = static_cast<int>(std::round((raw_nodes.at(static_cast<std::size_t>(id)).y - min_y) * precision));
        all_nodes.at(static_cast<std::size_t>(id)) = ProblemNode{
            id,
            scaled_x,
            scaled_y,
            raw_nodes.at(static_cast<std::size_t>(id)).demand,
            raw_nodes.at(static_cast<std::size_t>(id)).x,
            raw_nodes.at(static_cast<std::size_t>(id)).y
        };
    }

    // Separate depot from customers: depot is stored separately, customers get 0-based indices
    problem.depot = all_nodes.at(static_cast<std::size_t>(depot_id));
    for (int id = 1; id <= problem.dimension; ++id) {
        if (id != depot_id) {
            ProblemNode customer = all_nodes.at(static_cast<std::size_t>(id));
            customer.id = static_cast<int>(problem.nodes.size());
            problem.nodes.push_back(customer);
        }
    }

    validate_encoding_constants(problem);

    return problem;
}

