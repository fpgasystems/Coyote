#pragma once

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

#include "tsc_x86.h"

constexpr auto kCalibrate = false;
constexpr auto kCyclesRequired = 1e9;
constexpr auto kNumRunsDist = 1000;
constexpr auto kNumRunsDef = 100;

using namespace std::chrono;

/**
 * Exec times [ns]
 */
class Bench {
    std::vector<double> times;
    double avg_time = 0.0;
    int num_runs = 0;
    int num_runs_def = 0;

    void sortBench() { std::sort(times.begin(), times.end()); } 

public:
    Bench(int num_runs = kNumRunsDef) { this->num_runs_def = num_runs; } 

    // Number of runs for the average
    inline int getNumRuns() { return num_runs; }
    inline void setNumRuns(uint32_t n_runs) { num_runs = n_runs; }

    // Average run time
    inline double getAvg() { return avg_time; }

    // Statistics
    inline double getMin() { if(!times.empty()) return times[0]; else return 0; }
    inline double getMax() { if(!times.empty()) return times[times.size()-1]; else return 0; }
    inline double getP25() { if(!times.empty()) return times[(times.size()/4)-1]; else return 0; }
    inline double getP50() { if(!times.empty()) return times[(times.size()/2)-1]; else return 0; }
    inline double getP75() { if(!times.empty()) return times[((times.size()*3)/4)-1]; else return 0; }
    inline double getP95() { if(!times.empty()) return times[((times.size()*95)/100)-1]; else return 0; }
    inline double getP99() { if(!times.empty()) return times[((times.size()*99)/100)-1]; else return 0; }

    // Print results
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

    /**
     * Measure the function execution
     */
    template <class Func, typename... Args>
    void runtime(Func const &func, Args... args) {
        times.clear();
        
        // Warm-up
        if (kCalibrate) {
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
            num_runs = num_runs_def;
        }

        std::cout <<"N runs: " << num_runs << std::endl;

        // Average time
        auto begin_time = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < num_runs; ++i) {
            func(args...);
        }
        auto end_time = std::chrono::high_resolution_clock::now();

        double time = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - begin_time).count();
        avg_time = time / num_runs;
        /*
        for (int i = 0; i < kNumRunsDist; ++i) {
            begin_time = std::chrono::high_resolution_clock::now();
                func(args...);
            end_time = std::chrono::high_resolution_clock::now();
            
            time = std::chrono::duration_cast<std::chrono::nanoseconds>(end_time - begin_time).count();
            times.emplace_back(time);
        }
        */
        //sortBench();
        //printOut(); 
    }

};
