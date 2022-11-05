#pragma once

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h>
#include <sys/time.h>
#include <chrono>
#include <set>
#include <vector>
#include <sstream>

#include "cArbiter.hpp"

using namespace std;
using namespace std::chrono;

/**
 * @brief Tasks
 * 
 */

// Add + multiply
constexpr auto const defAddmul = 2; 
auto addmul = [](cThread *cthread, uint32_t size, uint32_t add, uint32_t mul) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);
    uint32_t *rMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defAddmul;

    // Prep
    cthread->setCSR(mul, 0); // Addition
    cthread->setCSR(add, 1); // Multiplication

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != defAddmul * mul + add) k = false;
    if (!k)  std::cout << "ERR:  Addmul failed!" << std::endl;

    // Free
    free((void*) hMem);
    free((void*) rMem);
};

// Stream statistics
constexpr auto const defMin = 10; 
constexpr auto const defMax = 20; 
auto minmaxsum = [](cThread *cthread, uint32_t size) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);
    
    // Fill
    uint32_t sum = 0;
    for(int i = 0; i < size/4; i++) {
        hMem[i] = i%2 ? defMin : defMax;
        sum += hMem[i];
    }

    // Prep
    cthread->setCSR(0x1, 0); // Start kernel

    // Invoke
    cthread->invoke({CoyoteOper::READ, (void*)hMem, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); } // Poll for completion

    // Check results
    if((cthread->getCSR(2) != defMin) || (cthread->getCSR(2) != defMax) || (sum != cthread->getCSR(4)))
    std::cout << "ERR:  MinMaxSum failed!" << std::endl;  

    // Free
    free((void*) hMem);
};

// Rotation
constexpr auto const defRot = 0xefbeadde; 
constexpr auto const expRot = 0xdeadbeef;
auto rotation = [](cThread *cthread, uint32_t size) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);
    uint32_t *rMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = defRot; 

    // Invoke
    cthread->invoke({CoyoteOper::TRANSFER, (void*)hMem, (void*)rMem, size, size});

    // Check results
    bool k = true;
    for(int i = 0; i < size/4; i++) 
        if(rMem[i] != expRot) k = false;
    std::cout << "ERR:  Rotate failed!" << std::endl;  

    // Free
    free((void*) hMem);
    free((void*) rMem);
};

// Testcount
auto testcount = [](cThread *cthread, uint32_t size, uint32_t type, uint32_t cond) {
    // Allocate some memory
    uint32_t *hMem = (uint32_t*) malloc(size);

    // Fill
    for(int i = 0; i < size/4; i++) 
        hMem[i] = i; 
    
    // Prep
    cthread->setCSR(type, 2); // Type of comparison
    cthread->setCSR(cond, 3); // Predicate
    cthread->setCSR(0x1, 0); // Start kernel

    // Invoke
    cthread->invoke({CoyoteOper::READ, (void*)hMem, size, true, false});
    while(cthread->getCSR(1) != 0x1) { nanosleep((const struct timespec[]){{0, 100L}}, NULL); }

    // Stats
    if(cthread->getCSR(4) != size/4) 
        std::cout << "ERR:  Testcount failed!" << std::endl;

    // Free
    free((void*) hMem);
};