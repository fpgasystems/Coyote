#include "fQ.hpp"

#include <iostream>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <netdb.h>

namespace fpga {

uint32_t fQ::gidToUint(int idx) {
    if(idx > 24) {
        std::cerr << "Invalid index for gitToUint" << std::endl;
        return 0;
    }
    char tmp[9];
    memset(tmp, 0, 9);
    uint32_t v32 = 0;
    memcpy(tmp, gid+idx, 8);
    sscanf(tmp, "%x", &v32);
    return ntohl(v32);
}

void fQ::uintToGid(int idx, uint32_t ip_addr) {
    std::ostringstream gidStream;
    gidStream << std::setfill('0') << std::setw(8) << std::hex << ip_addr;
    memcpy(gid+idx, gidStream.str().c_str(), 8);
}

void fQ::print(const char *name) {
    printf("%s:  LID 0x%04x, QPN 0x%06x, PSN 0x%06x, GID %s, REG 0x%04x, RKEY %#08x, VADDR %016lx, SIZE %08x\n",
         name, 0, qpn, psn, gid, region, rkey, vaddr, size);
}

std::string fQ::encode() {
    std::uint32_t lid = 0;
    std::ostringstream msgStream;
    msgStream << std::setfill('0') << std::setw(4) << std::hex << lid << " ";
    msgStream << std::setfill('0') << std::setw(6) << std::hex << qpn << " ";
    msgStream << std::setfill('0') << std::setw(6) << std::hex << (psn & 0xFFFFFF) << " ";  
    msgStream << std::setfill('0') << std::setw(4) << std::hex << (region & 0xf) << " "; 
    msgStream << std::setfill('0') << std::setw(8) << std::hex << rkey << " ";
    msgStream << std::setfill('0') << std::setw(16) << std::hex << vaddr << " ";
    msgStream << gid;

    std::string msg = msgStream.str();
    return msg;
}

void fQ::decode(char* buf, size_t len) {
    if (len < 60) {
        std::cerr << "ERR: unexpected length " << len << " in decode ib connection\n";
        return;
    }
    buf[4] = ' ';
    buf[11] = ' ';
    buf[18] = ' ';
    buf[23] = ' ';
    buf[32] = ' ';
    buf[49] = ' ';

    std::uint32_t lid = 0;
    //std::cout << "buf " << buf << std::endl;
    std::string recvMsg(buf, len);
    //std::cout << "string " << recvMsg << ", length: " << recvMsg.length() << std::endl;
    std::istringstream recvStream(recvMsg);
    recvStream >> std::hex >> lid >> qpn >> psn >> region;
    recvStream >> std::hex >> rkey >> vaddr >> gid;
}

}