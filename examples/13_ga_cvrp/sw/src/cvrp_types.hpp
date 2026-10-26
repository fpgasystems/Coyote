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

#ifndef CVRP_TYPES_HPP
#define CVRP_TYPES_HPP

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <iostream>

struct ProblemNode {
    int id = 0;
    int x = 0;
    int y = 0;
    int demand = 0;
    double raw_x = 0.0;
    double raw_y = 0.0;
};

struct ProblemInstance {
    std::string name;
    int capacity = 0;
    int dimension = 0;
    ProblemNode depot;
    std::vector<ProblemNode> nodes;
    int scaling = 1;
};

// Number of customers of a problem instance (all nodes except the depot)
constexpr std::size_t numCustomers(const ProblemInstance &problem) {
    return static_cast<std::size_t>(problem.dimension - 1);
}

struct TourGene {
    int node_id = 0;
    bool depot_after = false;

    bool operator==(const TourGene &rhs) const {
        return node_id == rhs.node_id && depot_after == rhs.depot_after;
    }

    bool operator!=(const TourGene &rhs) const {
        return !(*this == rhs);
    }
};

struct Individual {
    std::vector<TourGene> tour;
    std::uint32_t fitness = 0;

    bool operator==(const Individual &rhs) const {
        return fitness == rhs.fitness && tour == rhs.tour;
    }

    bool operator!=(const Individual &rhs) const {
        return !(*this == rhs);
    }

    bool validate(const ProblemInstance &problem, bool throw_on_error = true) const;

    friend std::ostream &operator<<(std::ostream &os, const Individual &ind) {
        os << "Fitness: " << ind.fitness << ", Tour: ";
        for (std::size_t i = 0; i < ind.tour.size(); ++i) {
            const auto &gene = ind.tour[i];
            os << gene.node_id;

            if (gene.depot_after) {
                if (i + 1 < ind.tour.size()) {
                    os << " | ";
                } else {
                    os << " |";
                }
            } else if (i + 1 < ind.tour.size()) {
                os << ", ";
            }
        }
        return os;
    }
};

// Floored Euclidean distance between two problem nodes
std::uint32_t floor_euclidean_distance(const ProblemNode &lhs, const ProblemNode &rhs);

// Exact double-precision Euclidean distance between two problem nodes using unscaled raw coordinates
double exact_euclidean_distance(const ProblemNode &lhs, const ProblemNode &rhs);

// Total tour distance of an individual (depot -> ... -> depot per route)
std::uint32_t compute_fitness(const ProblemInstance &problem, const Individual &individual);

// Exact total tour distance of an individual with real sqrt on unscaled coordinates
double compute_exact_fitness(const ProblemInstance &problem, const Individual &individual);

// Validates customer node uniqueness and vehicle capacity constraints of a solution
bool validate_solution(const ProblemInstance &problem, const Individual &individual, bool throw_on_error = true);

// Validates all individuals in a population
bool validate_population(const ProblemInstance &problem, const std::vector<Individual> &population, bool throw_on_error = true);

inline bool Individual::validate(const ProblemInstance &problem, bool throw_on_error) const {
    return validate_solution(problem, *this, throw_on_error);
}

/*
 * Build one individual from a customer visit order: greedily splits the order
 * into routes that respect the vehicle capacity and computes the fitness.
 */
Individual build_individual(const ProblemInstance &problem, const std::vector<int> &customer_order);

/*
 * Build a deterministic initial population of population_size distinct individuals by
 * drawing unique permutations with a fixed seed.
 */
std::vector<Individual> build_initial_population(const ProblemInstance &problem, std::size_t population_size, std::uint32_t population_seed);

#endif // CVRP_TYPES_HPP
