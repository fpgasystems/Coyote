
/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_COMMON_HPP_
#define _COYOTE_COMMON_HPP_

#include <chrono>
#include <ctime>
#include <string>

#include "BlockingQueue.hpp"

std::string get_current_time() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    auto tm = localtime(&time);
    char c_result[20];
    strftime(c_result, 20, "%T", tm);
    std::string result(c_result);
    return result;
}

#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)
#define LOG(LEVEL) std::cout << get_current_time() << " [" << LEVEL << "] " << __FILENAME__ << ":" << __LINE__ << ": "
#define ERROR(m) LOG("ERROR") << m << std::endl;
#define FATAL(m) LOG("FATAL") << m << std::endl;
#define ASSERT(m) LOG("ASSERT") << m << std::endl; assert(false);
#ifdef VERBOSE
#define DEBUG(m) LOG("DEBUG") << m << std::endl << std::flush;
#else
#define DEBUG(m) { }
#endif

namespace coyote {

enum thread_ids {
    OTHER_THREAD_ID,
    SIM_THREAD_ID,
    OUT_THREAD_ID
};

typedef struct {
    uint8_t id;
    int status;
} return_t;

BlockingQueue<return_t> return_queue;

int executeUnlessCrash(const std::function<void()> &lambda) {
    auto other_thread = std::thread([&lambda]{
        lambda();
        return_queue.push({OTHER_THREAD_ID, 0});
    });

    auto result = return_queue.pop();
    if (result.id != OTHER_THREAD_ID) { // VivadoRunner or OutputReader crashed
        FATAL("Thread with id " << (int) result.id << " crashed")
        std::terminate();
    }
    other_thread.join();
    return result.status;
}

}

#endif
