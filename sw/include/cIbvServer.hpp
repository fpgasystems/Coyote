#include <iostream>
#include <chrono>
#include <thread>
#include <unordered_map>
#include <atomic>
#include <utility>

#include "cDefs.hpp"
#include "cIbvCtx.hpp"

namespace fpga {

class cIbvServer
{
    
public:
    cIbvServer(size_t max_connections, int32_t vfid, const std::string& ip_addr);
    void exchangeQpServer(uint16_t port);
    void serve(uint16_t port);
    void serveInSeparateThread(uint16_t port);
    auto getQpair(uint32_t qpn) const -> cIbvCtx*;
    ~cIbvServer();

private:
    auto addQpair(ibvQ &qpair) -> cIbvCtx*;
    
    size_t max_connections = 0;
    int32_t server_vfid; 
    string server_ip;
    std::thread m_executor; 
    std::unordered_map<uint32_t , std::unique_ptr<cIbvCtx> > qpairs;
};

} // namespace fpga
