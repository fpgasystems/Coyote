#pragma once

#include <chrono>
#include <ctime>
#include <string>

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
#define LOG std::cout << get_current_time() << ": " << __FILENAME__
#define ERROR(m) LOG << "[ERROR]: " << m << std::endl;
#define FATAL(m) LOG << "[FATAL]: " << m << std::endl;
#define ASSERT(m) LOG << "[ASSERT]: " << m << std::endl; assert(false);
#ifdef VERBOSE
#define DEBUG(m) LOG << m << std::endl;
#else
#define DEBUG(m) { }
#endif
