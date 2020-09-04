#ifndef __FOP3_HPP__
#define __FOP3_HPP__

#include <iostream>
#include <locale>
#include <thread>

#include "fDev.hpp"
#include "fJob.hpp"
#include "fDefs.hpp"

using namespace std;

/**
 * FPGA excl. NOR bitwise job
 */
class fOp3 : public fJob {
private:
    uint64_t* src;
    uint64_t* dst;
    uint32_t len;

public:
    fOp3(uint64_t* src, uint64_t* dst, uint32_t len, uint32_t id, uint32_t priority)
    : fJob(id, priority, OPER_3) {
        this->src = src;
        this->dst = dst;
        this->len = len;
    }

    fOp3(uint64_t* mem, uint32_t len, uint32_t id, uint32_t priority)
    : fJob(id, priority, OPER_3) {
        this->src = mem;
        this->dst = mem;
        this->len = len;
    }

    void run() {
        fillData(src, len);
        fdev->transferData(src, dst, len, len/8, true);
        checkData(dst, len/8);
        //printData(dst, len/8);
    }

    void fillData(uint64_t *mem, uint32_t len) {
    for(uint32_t i = 0; i < len/8; i++) {
            if(i%8 == 1) {
                mem[i] = 0x0000000000000002;
            }
            else if(i%8 == 0) {
                mem[i] = 0x0000000000000005;
            }
            else {
                mem[i] = 0x0000000000000000;
            }
        }
    }

    void checkData(uint64_t *mem, uint32_t len) {
        bool k = false;
        for(uint32_t i = 0; i < len/8; i++) {
            if(mem[i] != 0xfffffffffffffff8) {
                k = true;
                cout << hex << mem[i] << dec << endl;
            }
        }
        if(k) cout << "Error excl. NOR" << endl;
    }

    void printData(uint64_t *mem, uint32_t len) {
        for(uint32_t i = 0; i < len/8; i++)
            cout << hex << mem[i] << endl;
    }
};



#endif