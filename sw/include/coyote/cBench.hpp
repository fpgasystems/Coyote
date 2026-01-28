/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
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

#ifndef _COYOTE_CBENCH_HPP_
#define _COYOTE_CBENCH_HPP_

#include <chrono>
#include <vector>
#include <algorithm>

#include <coyote/cDefs.hpp>

namespace coyote {

/**
 * @brief Helper class for benchmarking various functions in Coyote
 *
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
     * 
     * @param bench_func Function to be benchmarked
     * @param bench_args Arguments passed to benchmark function
     * @param prep_func Function executed before benchmark (any prep work)
     * @param prep_args Arguments passed to prep function
     * 
     * @note Even though this is a header file, we define the function here (but only this one, the others are defined in cBench.cpp)
     * The reason for that being is that at compile time get an -fpermissive warning of no definition for this function
     * However, declaring it here and defining it in cBench.cpp doesn't work as it requires a template specialiastion
     * See here for more details: https://isocpp.org/wiki/faq/templates#templates-defn-vs-decl
     */
    template <class BenchFunc, typename... BenchArgs, class PrepFunc, typename... PrepArgs>
    void execute(BenchFunc const &bench_func, BenchArgs... bench_args, PrepFunc const &prep_func, PrepArgs... prep_args) {
        // Clear previous results
        measured_times.clear();

        // Run a few warm-up runs; this is particularly useful for AVX architectures and code running on GPUs
        for (int i = 0; i < this->n_warmups; i++) {
            prep_func(prep_args...);
            bench_func(bench_args...);
        }

        // Run the benchmark for a given number of repetitions
        for (int i = 0; i < this->n_runs; i++) {
            // Calculate elapsed time - start timer, execute the function (which is given as an argument) and stop timer afterwards 
            prep_func(prep_args...);
            auto begin_time = std::chrono::high_resolution_clock::now();
            bench_func(bench_args...);
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

#endif // _COYOTE_CBENCH_HPP_
