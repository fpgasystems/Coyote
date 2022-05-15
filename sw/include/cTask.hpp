#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

using namespace fpga;

// Decl cThread
class cThread;

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

    virtual void run(cThread* cThread) = 0;    

    // Getters
    inline auto getTid() const { return tid; }
    inline auto getOid() const { return oid; }
    inline auto getPriority() const { return priority; }
};

/**
 * @brief Coyote task
 * 
 */
template<typename Func, typename... Args>
class cTask : public bTask {

    std::tuple<Args...> args;
    Func f;

public:

    explicit cTask(int32_t tid, int32_t oid, uint32_t priority, Func f, Args... args) 
        : f(f), args{args...}, bTask(tid, oid, priority) {}

    virtual void run(cThread* cthread) final {
        apply(f, std::tuple_cat(std::make_tuple(cthread), args));
    }
};
