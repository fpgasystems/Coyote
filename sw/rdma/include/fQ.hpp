#pragma once

#include <cstdint>
#include <string>
#include <cstring>

namespace fpga {

#define MSG_LEN 82

class fQ {
public:
    // Queue
    uint32_t qpn; 
    uint32_t psn; 
    uint32_t rkey;
    
    // Buffer
    uint64_t vaddr; 
    uint32_t size;
    
    // Node
    uint32_t region;

    // Global ID
    char gid[33];

    //
    fQ() { memset(gid, 0, 33); }

    std::string encode();
    void decode (char *buf, size_t len);

    uint32_t gidToUint(int idx);
    void uintToGid(int idx, uint32_t ip_addr);

    void print(const char *name);
    static uint32_t getLength() { return MSG_LEN; }
};

struct fQPair {
    fQ local;
    fQ remote;
};

} /* namespace fpga */