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
 */
class bFunc {
public:
    //
    virtual bThread* registerClientThread(int connfd, int32_t vfid, pid_t rpid, csDev dev, cSched *csched, void (*uisr)(int) = nullptr, ibvQ *q = nullptr) = 0;
};

}
