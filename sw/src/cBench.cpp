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
 
#include <coyote/cBench.hpp>

namespace coyote {

cBench::cBench(unsigned int n_runs, unsigned int n_warmups) { 
    this->n_runs = n_runs; 
    this->n_warmups = n_warmups;
} 

double cBench::getAvg() { 
    if(measured_times.empty()) { return NaN; }
    
    double avg_time = 0;
    for (const double &t : measured_times) {
        avg_time += t;
    }
    return avg_time / (double) measured_times.size(); 
}

double cBench::getMin() { if(!measured_times.empty()) return measured_times[0]; else return NaN; }

double cBench::getMax() { if(!measured_times.empty()) return measured_times[measured_times.size()-1]; else return NaN; }

double cBench::getP25() { if(!measured_times.empty()) return measured_times[(measured_times.size()/4)-1]; else return NaN; }

double cBench::getP50() { if(!measured_times.empty()) return measured_times[(measured_times.size()/2)-1]; else return NaN; }

double cBench::getP75() { if(!measured_times.empty()) return measured_times[((measured_times.size()*3)/4)-1]; else return NaN; }

double cBench::getP95() { if(!measured_times.empty()) return measured_times[((measured_times.size()*95)/100)-1]; else return NaN; }

double cBench::getP99() { if(!measured_times.empty()) return measured_times[((measured_times.size()*99)/100)-1]; else return NaN; }

}
