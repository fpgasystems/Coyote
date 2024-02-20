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
#include <signal.h> 


#include "cIbvServer.hpp"

/* Signal handler */
std::atomic<bool> am_stalled(false); 
void gotAnInt(int) {
    am_stalled.store(true);
    //throw std::runtime_error("Stalled, SIGINT caught");
}


using namespace std;

namespace fpga {

cIbvServer::cIbvServer(size_t max_connections, int32_t vfid, const std::string& ip_addr)
: max_connections{max_connections}, server_vfid{vfid}, server_ip{ip_addr}
{
    
}

void cIbvServer::exchangeQpServer(uint16_t port) {
    uint32_t recv_node;
    uint8_t ack;
    uint32_t n;
    int sockfd = -1, connfd;
    struct sockaddr_in server;
    char recv_buf[recvBuffSize];
    std::memset(recv_buf, 0, recvBuffSize);
    struct ibvQ qpair_recv;
    uint32_t lqpn;

    DBG2("Server side exchange started ...");

    sockfd = ::socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd == -1) 
        throw std::runtime_error("Could not create a socket");

    server.sin_family = AF_INET;
    server.sin_addr.s_addr = INADDR_ANY;
    server.sin_port = htons(port);

    if (::bind(sockfd, (struct sockaddr*)&server, sizeof(server)) < 0)
        throw std::runtime_error("Could not bind a socket");

    if (sockfd < 0 )
        throw std::runtime_error("Could not listen to a port: " + to_string(port));

    // Listen for conns
    listen(sockfd, max_connections);

    for (uint32_t i = 0; !am_stalled.load() && i < max_connections; ++i)
    {
        connfd = ::accept(sockfd, NULL, 0);
        if (connfd < 0) 
            throw std::runtime_error("Accept failed");

        // Read a queue
        if (::read(connfd, recv_buf, sizeof(ibvQ)) != sizeof(ibvQ)) {
            ::close(connfd);
            throw std::runtime_error("Could not read a remote queue");
        }
        memcpy(&qpair_recv, recv_buf, sizeof(ibvQ));

        // Generate the qpair. We can't pre-make these unlike in ibvQpMap, as we don't know how many clients will connect to us.
        cIbvCtx *ibv_qpair_conn = addQpair(qpair_recv);
        ibv_qpair_conn->setConnection(connfd);

        // Send a queue
        if (::write(connfd, &ibv_qpair_conn->getQpair()->local, sizeof(ibvQ)) != sizeof(ibvQ))  {
            ::close(connfd);
            throw std::runtime_error("Could not write a local queue");
        }

        // Write context and connection
        ibv_qpair_conn->writeContext(port);

        // ARP lookup
        ibv_qpair_conn->doArpLookup();

        std::cout << "Server syncing ..." << std::endl;
        ibv_qpair_conn->ibvSync(false);
        ibv_qpair_conn->ibvClear();
        ibv_qpair_conn->ibvSync(false);
        std::cout << "Server synced" << std::endl;
    }
}

auto cIbvServer::addQpair(ibvQ &qpair_remote) -> cIbvCtx*
{
    auto qpConn = std::make_unique<cIbvCtx>(server_vfid, getpid(), server_ip, qpair_remote.qpn & sidMask, qpair_remote.size, CoyoteAlloc::HPF);
    auto lqpn = qpConn->getQpair()->local.qpn;
    qpairs.emplace(lqpn, std::move(qpConn));
    qpConn->getQpair()->remote = qpair_remote;

    DBG2("Qpair exchanged, client ip_address : " << std::hex <<  qpair_remote.ip_addr << std::dec);
    qpConn->getQpair()->local.print("Local ");
    qpConn->getQpair()->remote.print("Remote ");

    return qpConn.get();
}

auto cIbvServer::getQpair(uint32_t qpn) const -> cIbvCtx*
{
    auto it = qpairs.find(qpn);
    if (it == qpairs.end()) return nullptr;
    return it->second.get();
}

void cIbvServer::serve(uint16_t port)
{
    // Sig handler, in case of stalling. Like in perf rdma, except we crash directly in sig handler
    struct sigaction sa;
    memset( &sa, 0, sizeof(sa) );
    sa.sa_handler = gotAnInt;
    sigfillset(&sa.sa_mask);
    sigaction(SIGINT,&sa,NULL);

    // Accept incoming clients and exchange qpairs one by one
    exchangeQpServer(port);
}

void cIbvServer::serveInSeparateThread(uint16_t port)
{
    m_executor = std::thread(&cIbvServer::serve, this, port);
}

cIbvServer::~cIbvServer()
{
    if(m_executor.joinable()) // default constructed thread not joinable
        m_executor.join();
}

} // namespace fpga
