#ifndef __FOP1_HPP__
#define __FOP1_HPP__

#include <iostream>
#include <locale>
#include <thread>

#include "fDev.hpp"
#include "fJob.hpp"
#include "fDefs.hpp"

using namespace std;

/**
 * FPGA OR bitwise job
 */
class fOp1 : public fJob {
private:
    uint64_t* src;
    uint64_t* dst;
    uint32_t len;

public:
    fOp1(uint64_t* src, uint64_t* dst, uint32_t len, uint32_t id, uint32_t priority)
    : fJob(id, priority, OPER_1) {
        this->src = src;
        this->dst = dst;
        this->len = len;
    }

    fOp1(uint64_t* mem, uint32_t len, uint32_t id, uint32_t priority)
    : fJob(id, priority, OPER_1) {
        this->src = mem;
        this->dst = mem;
        this->len = len;
    }

    void run() {
        fillData(src, len);
        fdev->transferData(src, dst, len, len/8, true);
        //checkData(dst, len/8);
        //printData(dst, len/8);
    }

    void fillData(uint64_t *mem, uint32_t len) {
    for(uint32_t i = 0; i < len/8; i++) {
            if(i%2) {
                mem[i] = 0x55555555aaaaaaaa;
            }
            else {
                mem[i] = 0x5555555555555555;
            }
        }
    }

    void checkData(uint64_t *mem, uint32_t len) {
        bool k = false;
        for(uint32_t i = 0; i < len/8; i++) {
            if(mem[i] != 0x55555555ffffffff)
                k = true;
        }
        if(k) cout << "Error OR" << endl;
    }

    void printData(uint64_t *mem, uint32_t len) {
        for(uint32_t i = 0; i < len/8; i++)
            cout << hex << mem[i] << endl;
    }
};



#endif