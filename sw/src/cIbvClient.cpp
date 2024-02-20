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

#include "cIbvClient.hpp"

using namespace std;

namespace fpga {

// ======-------------------------------------------------------------------------------
/// Public
// ======-------------------------------------------------------------------------------

uint32_t cIbvClient::addQpair(const char *trgt_addr, uint16_t trgt_port, int32_t vfid, pid_t hpid, string ibv_addr, int32_t sid, uint32_t n_pages, CoyoteAlloc calloc) 
{
    auto qpair = std::make_unique<cIbvCtx>(vfid, hpid, ibv_addr, sid, n_pages, calloc);

    // Get qpn
    uint32_t qpn = qpair->getQpair()->local.qpn;

    if(qpairs.find(qpn) != qpairs.end())
        throw std::runtime_error("Queue pair already exists");
    
    qpairs.emplace(qpn, std::move(qpair));
    DBG1("Queue pair created, qpn: " << qpn);

    exchangeQpClient(qpn, trgt_addr, trgt_port);

    return qpn;
}

uint32_t cIbvClient::addQpair(const char *trgt_addr, uint16_t trgt_port, cThread *cthread, string ibv_addr, int32_t sid, void *vaddr, uint32_t size) 
{
    auto qpair = std::make_unique<cIbvCtx>(cthread, ibv_addr, sid);
    qpair->initLocalBuffs(vaddr, size);

    // Get qpn
    uint32_t qpn = qpair->getQpair()->local.qpn;

    if(qpairs.find(qpn) != qpairs.end())
        throw std::runtime_error("Queue pair already exists");
    
    qpairs.emplace(qpn, std::move(qpair));
    DBG1("Queue pair created, qpn: " << qpn);

    exchangeQpClient(qpn, trgt_addr, trgt_port);

    return qpn;
}

cIbvCtx* cIbvClient::getQpairCtx(uint32_t qpn) const
{
    auto ret_it = qpairs.find(qpn);
    if (ret_it == qpairs.end()) return nullptr;
    return ret_it->second.get();
}

void cIbvClient::removeQpair(uint32_t qpn) {
    if(qpairs.find(qpn) != qpairs.end()) {
        qpairs[qpn]->closeConnection();
        qpairs.erase(qpn);
    }
}

void* cIbvClient::getBufferPtr(uint32_t qpn) {
    if(qpairs.find(qpn) != qpairs.end()) {
        return (qpairs[qpn]->getQpair()->local.vaddr);
    }

    return nullptr;
}
uint32_t cIbvClient::getBufferSize(uint32_t qpn) {
    if(qpairs.find(qpn) != qpairs.end()) {
        return qpairs[qpn]->getQpair()->local.size;
    }

    return 0;
}

void cIbvClient::exchangeQpClient(uint32_t qpn, const char *trgt_addr, uint16_t trgt_port) {
    struct addrinfo *res, *t;
    uint8_t ack;
    struct addrinfo hints = {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    char* service;
    int n = 0;
    int sockfd = -1;
    char recv_buf[recvBuffSize];
    memset(recv_buf, 0, recvBuffSize);
    cIbvCtx *qp_ctx;

    DBG2("Slave side exchange started ...");

    if (asprintf(&service, "%d", trgt_port) < 0)
        throw std::runtime_error("asprintf() failed");

    n = getaddrinfo(trgt_addr, service, &hints, &res);
    if (n < 0) {
        free(service);
        throw std::runtime_error("getaddrinfo() failed");
    }

    if(qpairs.find(qpn) != qpairs.end()) {
        qp_ctx = qpairs[qpn].get();
    }

    for (t = res; t; t = t->ai_next) {
        sockfd = ::socket(t->ai_family, t->ai_socktype, t->ai_protocol);
        if (sockfd >= 0) {
            if (!::connect(sockfd, t->ai_addr, t->ai_addrlen)) {
                break;
            }
            ::close(sockfd);
            sockfd = -1;
        }
    }

    if (sockfd < 0)
        throw std::runtime_error("Could not connect to master: " + std::string(trgt_addr) + ":" + to_string(trgt_port));

    // Send a queue
    if (::write(sockfd, &qp_ctx->getQpair()->local, sizeof(ibvQ)) != sizeof(ibvQ)) {
        ::close(sockfd);
        throw std::runtime_error("Could not write a local queue");
    }

    // Read a queue
    if(::read(sockfd, recv_buf, sizeof(ibvQ)) != sizeof(ibvQ)) {
        ::close(sockfd);
        throw std::runtime_error("Could not read a remote queue");
    }
        
    qp_ctx->setConnection(sockfd);

    ibvQp *qpair = qp_ctx->getQpair();
    memcpy(&qpair->remote, recv_buf, sizeof(ibvQ));
    DBG2("Qpair number: " << qpn);
    qpair->local.print("Local ");
    qpair->remote.print("Remote");

    // Write context and connection
    qp_ctx->writeContext(trgt_port);

    // ARP lookup
    qp_ctx->doArpLookup();

    std::cout << "Client syncing ..." << std::endl;
    qp_ctx->ibvSync(false);
    qp_ctx->ibvClear();
    qp_ctx->ibvSync(false);
    std::cout << "Client synced" << std::endl;

    if (res) 
        freeaddrinfo(res);
    free(service);
}

}
