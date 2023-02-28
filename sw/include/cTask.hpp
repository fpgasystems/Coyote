#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

namespace fpga {

// Decl cProcess
class cProcess;

/**
 * @brief Base task, abstract
 * 
 */
class bTask {
    int32_t tid;
    int32_t oid;
    uint32_t priority;

public:
    bTask(int32_t tid, int32_t oid, uint32_t priority) : tid(tid), oid(oid), priority(priority) {}

    virtual int32_t run(cProcess* cproc) = 0;    

    // Getters
    inline auto getTid() const { return tid; }
    inline auto getOid() const { return oid; }
    inline auto getPriority() const { return priority; }
};

/**
 * @brief Coyote task
 * 
 * This is a task abstraction. Each cTask is scheduled to one cThread object.
 * It ultimately executes within one cProcess.
 * cTask is made of arbitrary user variadic functions.
 * 
 */
template<typename Func, typename... Args>
class cTask : public bTask {

    std::tuple<Args...> args;
    Func f;

public:

    explicit cTask(int32_t tid, int32_t oid, uint32_t priority, Func f, Args... args) 
        : f(f), args{args...}, bTask(tid, oid, priority) {}

    virtual int32_t run(cProcess* cproc) final {
        int32_t tmp = apply(f, std::tuple_cat(std::make_tuple(cproc), args));
        return tmp;
    }
};

}
