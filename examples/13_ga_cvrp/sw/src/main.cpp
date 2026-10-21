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

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

#include <boost/program_options.hpp>
#include <coyote/cDefs.hpp>

#include "coyote_ga.hpp"
#include "encoding_validator.hpp"
#include "genome_hash.hpp"
#include "problem_parser.hpp"

int main(int argc, char *argv[]) {
    try {
        coyote_ga::CoyoteAppConfig config{};

        boost::program_options::options_description runtime_options("Coyote CVRP GA Options");
        runtime_options.add_options()
            (",h", "Produce help message")
            (",f", boost::program_options::value<std::string>(&config.vrp_file)->default_value("../../problem_instances/P-n40-k5.vrp"), "Path to the CVRP instance file")
            (",p", boost::program_options::value<std::size_t>(&config.population_size_multiplier)->default_value(20), "Population size multiplier (population_size = dimension * multiplier)")
            (",g", boost::program_options::value<std::size_t>(&config.ga_params.n_generations)->default_value(100), "Number of generations")
            (",e", boost::program_options::value<double>(&config.ga_params.n_best_keep)->default_value(5.0), "Elitism percentage (% of best individuals to keep across generations)")
            (",s", boost::program_options::value<std::uint32_t>(&config.ga_params.seed)->default_value(0xC0FFEEu), "Random seed")
            (",k", boost::program_options::value<int>(&config.two_opt_k)->default_value(20), "Number of 2-opt iterations per subtour (k)")
            (",r", boost::program_options::value<bool>(&config.two_opt_enable_precheck)->default_value(false), "Enable precheck for 2-opt moves (1 = enable, 0 = disable)")
            (",c", boost::program_options::value<int>(&config.crossover_prob)->default_value(100), "Crossover probability (0 to 100)")
            (",m", boost::program_options::value<int>(&config.mutation_prob)->default_value(10), "Mutation probability (0 to 100)")
            (",o", boost::program_options::value<std::string>(&config.output_file)->default_value(""), "Path to output JSON file")
            (",t", boost::program_options::bool_switch(&config.smoke_test), "Run a single generation smoke test on FPGA and exit");

        boost::program_options::variables_map command_line_arguments;
        boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
        boost::program_options::notify(command_line_arguments);

        if (command_line_arguments.count("-h")) {
            std::cout << runtime_options << std::endl;
            return EXIT_SUCCESS;
        }

        HEADER("CLI PARAMETERS:");
        std::cout << "Population size multiplier: " << config.population_size_multiplier << std::endl;
        std::cout << "Number of generations: " << config.ga_params.n_generations << std::endl;
        std::cout << "Elitism percentage: " << config.ga_params.n_best_keep << "%" << std::endl;
        std::cout << "Seed: " << config.ga_params.seed << std::endl;
        std::cout << "Two-opt k: " << config.two_opt_k << std::endl;
        std::cout << "Two-opt enable precheck: " << (config.two_opt_enable_precheck ? "ENABLED" : "DISABLED") << std::endl;
        std::cout << "Crossover probability: " << config.crossover_prob << "%" << std::endl;
        std::cout << "Mutation probability: " << config.mutation_prob << "%" << std::endl;
        std::cout << "Output file: " << (config.output_file.empty() ? "(none)" : config.output_file) << std::endl;
        std::cout << "Smoke test mode: " << (config.smoke_test ? "ENABLED" : "DISABLED") << std::endl;
        std::cout << "Genome hasher: " << get_hash_backend_name() << std::endl;
        std::cout << "VRP file: " << config.vrp_file << std::endl << std::endl;

        const ProblemInstance problem = parse_vrp(config.vrp_file);
        validate_encoding_constants(problem);

        std::size_t pop_size = problem.dimension * config.population_size_multiplier;
        if (pop_size % 2 != 0) {
            pop_size += 1;
        }
        config.ga_params.pop_size = pop_size;

        std::cout << "Loaded problem: " << problem.name << std::endl;
        std::cout << "Dimension: " << problem.dimension << std::endl;
        std::cout << "Vehicle capacity: " << problem.capacity << std::endl;
        std::cout << "Precision: " << problem.scaling << std::endl;
        std::cout << "Total population size: " << pop_size << std::endl;

        if (config.smoke_test) {
            bool all_passed = coyote_ga::run_smoke_tests_all(problem, config);
            return all_passed ? EXIT_SUCCESS : EXIT_FAILURE;
        }

        GASummary summary = coyote_ga::run_pipelined_ga(problem, config);
        summary.print();

        if (!config.output_file.empty()) {
            summary.save_json(config.output_file, problem);
            std::cout << "Saved experiment output to: " << config.output_file << std::endl;
        }

        return EXIT_SUCCESS;
    } catch (const std::exception &e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return EXIT_FAILURE;
    }
}
