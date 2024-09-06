#pragma once

#include "cDefs.hpp"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <chrono>
#include <cmath>
#include <vector>
#include <iostream>
#include <algorithm>
#include <iomanip>

#ifdef EN_AVX
#include "tsc_x86.h"
#endif

constexpr auto kCalibrate = false;
constexpr auto kDistribute = false;
constexpr auto kCyclesRequired = 1e9;
constexpr auto kNumRunsDist = 1000;
constexpr auto kNumRunsDef = 100;

using namespace std::chrono;

/**
 * Exec times [ns]
 * 
 * Utility tool that allows to benchmark function execution with lots of added statistics: 
 */
class cBench {
    // Variables for later usage 
    double avg_time = { 0.0 }; // average time 
    int num_runs = { 0 }; // number of (done) runs
    int num_runs_def = { 0 }; // number of predefined runs 
    bool calibrate = { false }; // Bool: Should we habe calibration runs? 
    bool distribute = { false }; // Should we get a timing distribution from our measurement? 

    // Accummulated
    std::vector<double> times; // Vector holds all times that are measured

    void sortBench() { std::sort(times.begin(), times.end()); } // Function to sort time-values in the vector 

public:

    // Constructor: Define how many function runs the benchmarking suite should do, whether it should do a warm-up run for calibration first and whether it should display a distribution of results 
    cBench(int num_runs = kNumRunsDef, bool calibrate = kCalibrate, bool distribute = kDistribute) { 
        this->num_runs_def = num_runs; 
        this->calibrate = calibrate; 
        this->distribute = distribute;
    } 

    /**
     * Measure the function execution
     * 
     * Functional programming + variadic function: Function takes another function as argument +
     * arbitrary number of other arguments. 
     * 
     * 
     */
    template <class Func, typename... Args>
    void runtime(Func const &func, Args... args) {
        times.clear();

#ifdef EN_AVX    
        // Warm-up: Do some calibration runs in the first place 
        if (calibrate) {
            num_runs = 1;
            while (num_runs < (1 << 14)) {
                const auto start = start_tsc();
                for (int i = 0; i < num_runs; ++i) {
                    func(args...);
                }
                const auto cycles = stop_tsc(start);

                if (cycles >= kCyclesRequired)
                    break;

                num_runs *= 2;
            }
        } else {
#endif
            num_runs = num_runs_def;
#ifdef EN_AVX  
        }
#endif

        //DBG2("Number of bench runs: " << num_runs);

        // Average time - start timer, execute the function (which is given as argument) for the required number of times and stop timer afterwards 
        auto begin_time = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < num_runs; ++i) {
            func(args...);
        }
        auto end_time = std::chrono::high_resolution_clock::now();

        // Calculate time from start and end, divide by number of executions for average time 
        double time = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - begin_time).count();
        avg_time = time / num_runs;

        // Latency distribution - get the time for every single repetition of the function call, store that intermediate timing result in the time vector and sort it 
        if(distribute) {       
            for (int i = 0; i < kNumRunsDist; ++i) {
                // Take time and start the function in between 
                begin_time = std::chrono::high_resolution_clock::now();
                    func(args...);
                end_time = std::chrono::high_resolution_clock::now();
                
                time = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - begin_time).count();
                times.emplace_back(time);
            }

            sortBench();
            printOut(); 
        }
    }

    // Number of runs for the average
    inline auto getNumRuns() { return num_runs; }
    inline auto setNumRuns(uint32_t n_runs) { num_runs = n_runs; }

    // Average run time
    inline auto getAvg() { return avg_time; }

    // Statistics - get percentile timings etc. 
    inline auto getMin() { if(!times.empty()) return times[0]; else return 0.0; }
    inline auto getMax() { if(!times.empty()) return times[times.size()-1]; else return 0.0; }
    inline auto getP25() { if(!times.empty()) return times[(times.size()/4)-1]; else return 0.0; }
    inline auto getP50() { if(!times.empty()) return times[(times.size()/2)-1]; else return 0.0; }
    inline auto getP75() { if(!times.empty()) return times[((times.size()*3)/4)-1]; else return 0.0; }
    inline auto getP95() { if(!times.empty()) return times[((times.size()*95)/100)-1]; else return 0.0; }
    inline auto getP99() { if(!times.empty()) return times[((times.size()*99)/100)-1]; else return 0.0; }

    // Print results - advanced statistics are printed, including avg and percentiles 
    void printOut() {
        std::ios_base::fmtflags f(std::cout.flags());

        std::cout << "Average time: " << getAvg() << " ns" << std::endl;
        std::cout << "Max time: "     << getMax() << " ns" << std::endl;
        std::cout << "Min time: "     << getMin() << " ns" << std::endl;
        std::cout << "Median: "       << getP50() << " ns" << std::endl;
        std::cout << "25th: "         << getP25() << " ns" << std::endl;
        std::cout << "75th: "         << getP75() << " ns" << std::endl;
        std::cout << "95th: "         << getP95() << " ns" << std::endl;
        std::cout << "99th: "         << getP99() << " ns" << std::endl;

        std::cout.flags( f );
    }

};
