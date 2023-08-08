#include "ibvStructs.hpp"

#include <iostream>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <netdb.h>

namespace fpga {
    
uint32_t ibvQ::gidToUint(int idx) {
    if(idx > 24) {
        std::cerr << "Invalid index for gidToUint" << std::endl;
        return 0;
    }
    char tmp[9];
    memset(tmp, 0, 9);
    uint32_t v32 = 0;
    memcpy(tmp, gid+idx, 8);
    sscanf(tmp, "%x", &v32);
    return ntohl(v32);
}

void ibvQ::uintToGid(int idx, uint32_t ip_addr) {
    std::ostringstream gidStream;
    gidStream << std::setfill('0') << std::setw(8) << std::hex << ip_addr;
    memcpy(gid+idx, gidStream.str().c_str(), 8);
}

void ibvQ::print(const char *name) {
    printf("%s: QPN 0x%06x, PSN 0x%06x, VADDR %016lx, SIZE %08x, IP 0x%08x,\n",
         name, qpn, psn, (uint64_t)vaddr, size, ip_addr);
}

ibvQpPool::ibvQpPool(int32_t n_el) {
    n_free_el = n_el;
    for(int i = 0; i < n_el; i++) {
            pool[i].id = i;
            pool[i].next = &pool[i+1];
        }
        pool[n_el-1].id = n_el - 1;
        curr_el = pool;
}

ibvQpPool::~ibvQpPool() {
    delete pool;
}

int32_t ibvQpPool::acquire() {
    if(n_free_el) {
        n_free_el--;
        int32_t tmp_id = curr_el->id;
        curr_el->free = false;
        curr_el = curr_el->next;
        return tmp_id;
    } else 
        return -1;
}

bool ibvQpPool::release(int32_t id) {
    if(!pool[id].free) {
        pool[id].next = curr_el;
        curr_el = &pool[id];
        n_free_el++;
        return true;
    } else 
        return false;
}

std::atomic<uint32_t> ibvQp::curr_id;

}