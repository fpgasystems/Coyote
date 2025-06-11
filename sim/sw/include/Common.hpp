#pragma once

#include <chrono>
#include <ctime>
#include <string>

#include "blocking_queue.hpp"

std::string get_current_time() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    auto tm = localtime(&time);
    char c_result[20];
    strftime(c_result, 20, "%T", tm);
    std::string result(c_result);
    return result;
}

#define VERBOSE
#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)
#define LOG std::cout << get_current_time() << ": " << __FILENAME__
#define ERROR(m) LOG << "[ERROR]: " << m << std::endl;
#define FATAL(m) LOG << "[FATAL]: " << m << std::endl;
#define ASSERT(m) LOG << "[ASSERT]: " << m << std::endl; assert(false);
#ifdef VERBOSE
#define DEBUG(m) LOG << ": " << m << std::endl << std::flush;
#else
#define DEBUG(m) { }
#endif

namespace fpga {

enum thread_ids {
    OTHER_THREAD_ID,
    SIM_THREAD_ID,
    OUT_THREAD_ID
};

typedef struct {
    uint8_t id;
    int status;
} return_t;

blocking_queue<return_t> return_queue;

int executeUnlessCrash(const std::function<void()> &lambda) {
    auto other_thread = thread([&lambda]{
        lambda();
        return_queue.push({OTHER_THREAD_ID, 0});
    });

    auto result = return_queue.pop();
    if (result.id != OTHER_THREAD_ID) { // VivadoRunner or OutputReader crashed
        FATAL("Thread with id " << (int) result.id << " crashed")
        terminate();
    }
    other_thread.join();
    return result.status;
}

}
