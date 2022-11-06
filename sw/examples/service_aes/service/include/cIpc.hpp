#pragma once

#include <cstdint>
#include <string>
#include <cstring>
#include <atomic>

// Runtime
constexpr auto const socketName     = "/tmp/aes";
constexpr auto const recvBuffSize   = 1024;
constexpr auto const opCodeRun      = 0;
constexpr auto const opCodeClose    = 1;
constexpr auto const ackCode        = 0;
constexpr auto const nAckCode       = 1;
constexpr auto const targetRegion   = 0;
constexpr auto const keyCtrlReg     = 0;
constexpr auto const keyLowReg      = 1;
constexpr auto const keyHighReg     = 2;
constexpr auto const keyProp        = 0x1;


// Comm
struct msgType {
protected:
    static std::atomic<int32_t> curr_tid;
public:
    int32_t  tid;
    uint64_t src;
    uint32_t len;
    uint64_t key_low;
    uint64_t key_high;

    msgType() : tid(curr_tid++) {}
    msgType(uint64_t src, uint32_t len, uint64_t key_low, uint64_t key_high) :
        tid(curr_tid++), src(src), len(len), key_low(key_low), key_high(key_high) {}
};

std::atomic<int32_t> msgType::curr_tid;