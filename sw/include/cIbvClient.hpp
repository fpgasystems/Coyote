#include <iostream>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <random>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <string>

#include "cDefs.hpp"
#include "cIbvCtx.hpp"

using namespace std;

namespace fpga {

/**
 * @brief ibvProxy 
 * 
 */
class cIbvClient {
    /* Queue pairs */
    std::unordered_map<uint32_t, std::unique_ptr<cIbvCtx>> qpairs;

    /* Connection */
    void exchangeQpClient(uint32_t sid, const char *trgt_addr, uint16_t trgt_port);

public:

    cIbvClient () {}
    ~cIbvClient() {}

    /**
     * @brief Queue pair management
     * 
     * @param vfid - vFPGA ID
     * @param ibv_addr - InfiniBand IP address (local)
     * @param n_pages - number of hugepages in a buffer
     * @param qpn - queue pair number
     * @param trgt_addr - target TCP/IP address (remote)
     * @param trgt_port - target port number (remote)
     * 
     * @return auto - queue pair number
     */
    uint32_t addQpair(const char *trgt_addr, uint16_t trgt_port, int32_t vfid, pid_t hpid, string ibv_addr, int32_t sid, uint32_t n_pages, CoyoteAlloc calloc = CoyoteAlloc::THP);
    uint32_t addQpair(const char *trgt_addr, uint16_t trgt_port, cThread *cthread, string ibv_addr, int32_t sid, void *vaddr, uint32_t size);
    cIbvCtx* getQpairCtx(uint32_t qpn) const;
    void removeQpair(uint32_t qpn);

    /**
     * @brief Get buffer info
     * 
     * @param qpn - queue pair number
     * 
     * @return char* - pointer of the buffer
     * @return uint32_t - buffer size
     */
    void* getBufferPtr(uint32_t qpn);
    uint32_t getBufferSize(uint32_t qpn);

};


}
