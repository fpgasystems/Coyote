#pragma once

#include "cDefs.hpp"

#include <tuple>
#include <type_traits>
#include <memory>
#include <iostream>
#include <cstddef>
#include <utility>

namespace fpga {

// Decl cThread
template<typename Cmpl>
class cThread;

/**
 * @brief Base task, abstract
 * 
 */
template<typename Cmpl>
class bTask {
    int32_t tid;
    int32_t oid;
    uint32_t priority;

public:
    bTask(int32_t tid, int32_t oid, uint32_t priority) : tid(tid), oid(oid), priority(priority) {}
    virtual ~bTask() {}

    virtual Cmpl run(cThread<Cmpl> *cthread) = 0;    

    // Getters
    inline auto getTid() const { return tid; }
    inline auto getOid() const { return oid; }
    inline auto getPriority() const { return priority; }
};

/**
 * @brief Coyote task
 * 
 * This is a task abstraction. Each cTask is scheduled to one cThread object.
 * cTask is made of arbitrary user variadic functions.
 * 
 */
template<typename Cmpl, typename Func, typename... Args>
class cTask : public bTask<Cmpl> {

    std::tuple<Args...> args;
    Func f;

public:

    explicit cTask(int32_t tid, int32_t oid, uint32_t priority, Func f, Args... args) 
        : f(f), args{args...}, bTask<Cmpl>(tid, oid, priority) {
            # ifdef VERBOSE
                std::cout << "cTask: Called the constructor with oid " << oid << ", priority " << priority << std::endl; 
            # endif
        }

    virtual Cmpl run(cThread<Cmpl>* cthread) final {
        # ifdef VERBOSE
            std::cout << "cTask: Run the task." << std::endl; 
        # endif

        Cmpl tmp = apply(f, std::tuple_cat(std::make_tuple(cthread), args));
        return tmp;
    }
};

}
