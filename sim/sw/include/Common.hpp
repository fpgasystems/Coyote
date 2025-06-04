#pragma once

#include <chrono>
#include <ctime>
#include <string>

std::string get_current_time() {
    auto now = std::chrono::system_clock::now();
    auto time = std::chrono::system_clock::to_time_t(now);
    std::string result = std::ctime(&time);
    return result.substr(11, result.size() - 17);
}

#define LOG std::cout << get_current_time() << ": "