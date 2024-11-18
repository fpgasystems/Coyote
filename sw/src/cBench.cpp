// TODO: Add licence & file description; think about documentation/comments here
#include "cBench.hpp"

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
