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

#define LOG std::cout << get_current_time() << ": "