#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

#include "bThread.hpp"

namespace fpga {

/**
 * @brief User functions, base
 * 
 * To be inherited by the cFunc-class 
 * 
 */
class bFunc {
public:
    // General notion: virtual functions are expected to be overwritten in derived classes 

    // Function to register a client thread (also returns such a thread). Takes the following parameters as input: 
    // connfd: connection file descriptor 
    // vfid: vFPGA ID 
    // rpid: remote process ID 
    // dev: Device ID 
    // cSched: Pointer to a scheduler 
    // Pointer to a User Interrupt Service Routine 
    virtual bThread* registerClientThread(int connfd, int32_t vfid, pid_t rpid, uint32_t dev, cSched *csched, void (*uisr)(int) = nullptr) = 0;

    // Virtual function to start 
    virtual void start() = 0;

    // Virtual destructor of the bFunc 
    virtual ~bFunc() {}
};

}
