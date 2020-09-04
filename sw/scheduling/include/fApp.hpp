#ifndef __FAPP_HPP__
#define __FAPP_HPP__

#include <iostream>
#include <locale>

#include "fDev.hpp"
#include "fJob.hpp"
#include "fDefs.hpp"

using namespace std;

class fApp : public fJob {
private:


public:
    fApp(uint32_t id, uint32_t priority)
    : fJob(id, priority, OPER_APP) {}

    void run() {
        cout << "User function" << endl;
    }

};


#endif