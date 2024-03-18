#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

namespace fpga {

/**
 * @brief User functions, base
 * 
 */
class bFunc {
public:
    //
    virtual void registerClientThread(int connfd, int32_t vfid, pid_t rpid, csDev dev, void (*uisr)(int) = nullptr) = 0;
    virtual void requestRecv() = 0;
    virtual void responseSend() = 0;
};

}
