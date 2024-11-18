

// TODO: Add licence & file description

#ifndef C_BENCH_HPP
#define C_BENCH_HPP

#include <chrono>
#include <vector>
#include <algorithm>

#include "cDefs.hpp"

namespace coyote {

/**
 * Helper class for benchmarking various functions in Coyote
 * At a high-level, it executes some function a number of times and records its duration
 * Then, it can be used for outputting run-time statistics, such as average, minimum, maximum etc.
 */
class cBench {
    private:
        unsigned int n_runs;
        unsigned int n_warmups;
        std::vector<double> measured_times;
        
    public:
        /// Default constructor; user can define number of test runs and also the number of warm-up runs, which don't affect time measurements
        cBench(unsigned int n_runs = 1000, unsigned int n_warmups = 100);

        /**
        * Benchmark function execution (measure the duration)
        * 
        * We use functional programming + variadic templates: 
        * A function takes another function as argument + arbitrary number of other arguments
        * For examples on how to use this, see examples_sw/perf_local/main.cpp
        * 
        * @param func Function to be execute
        * @param args Arguments passed to function
        * 
        * @note Even though this is a header file, we define the function here (but only this one, the others are defined in cBench.cpp)
        * The reason for that being is that at compile time get an -fpermissive warning of no definition for this function
        * However, declaring it here and defining it in cBench.cpp doesn't work as it requires a template specialiastion
        * See here for more details: https://isocpp.org/wiki/faq/templates#templates-defn-vs-decl
        */
        template <class Func, typename... Args>
        void execute(Func const &func, Args... args) {
            // Clear previous results
            measured_times.clear();

            // Run a few warm-up runs; this is particularly useful for AVX architectures and code running on GPUs
            for (int i = 0; i < this->n_warmups; i++) {
                func(args...);
            }

            // Run the benchmark for a given number of repetitions
            for (int i = 0; i < this->n_runs; i++) {
                // Calculate elapsed time - start timer, execute the function (which is given as an argument) and stop timer afterwards 
                auto begin_time = std::chrono::high_resolution_clock::now();
                func(args...);
                auto end_time = std::chrono::high_resolution_clock::now();
                double measured_time = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - begin_time).count();
                measured_times.emplace_back(measured_time);
            }

            // Sort the results after logging to a file; enables easier calculation of the statistics below
            std::sort(measured_times.begin(), measured_times.end());
        }
        
        /// Returns the mean execution time; averaged over n_runs
        double getAvg();

        /// Returns the minimum execution time out of the n_runs recorded times
        double getMin();

        /// Returns the maximum execution time out of the n_runs recorded times
        double getMax();

        /// Returns the P25 execution time out of the n_runs recorded times
        double getP25();

        /// Returns the P50 execution time out of the n_runs recorded times
        double getP50();

        /// Returns the P75 execution time out of the n_runs recorded times
        double getP75();

        /// Returns the P95 execution time out of the n_runs recorded times
        double getP95();

        /// Returns the P99 execution time out of the n_runs recorded times
        double getP99();
    };
}

#endif

