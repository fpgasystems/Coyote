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

#include "ibvQpMap.hpp"

using namespace std;

constexpr auto const msgNAck = 0;
constexpr auto const msgAck = 1;
constexpr auto const recvBuffSize = 1024;

namespace fpga {

void ibvQpMap::addQpair(uint32_t qpid, int32_t vfid, string ip_addr, uint32_t n_pages) {
    if(qpairs.find(qpid) != qpairs.end())
        throw std::runtime_error("Queue pair already exists");

    auto qpair = std::make_unique<ibvQpConn>(vfid, ip_addr, n_pages);
    qpairs.emplace(qpid, std::move(qpair));
    DBG1("Queue pair created, qpid: " << qpid);
} 

void ibvQpMap::removeQpair(uint32_t qpid) {
    if(qpairs.find(qpid) != qpairs.end())
        qpairs.erase(qpid);
}

ibvQpConn* ibvQpMap::getQpairConn(uint32_t qpid) {
    if(qpairs.find(qpid) != qpairs.end())
        return qpairs[qpid].get();

    return nullptr;
}

void ibvQpMap::exchangeQpMaster(uint16_t port) {
    uint32_t recv_qpid;
    uint8_t ack;
    uint32_t n;
    int sockfd = -1, connfd;
    struct sockaddr_in server;
    char recv_buf[recvBuffSize];
    memset(recv_buf, 0, recvBuffSize);

    DBG2("Master side exchange started ...");

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

    // Listen for slave conns
    int n_qpairs = qpairs.size();
    listen(sockfd, n_qpairs);

    for(int i = 0; i < n_qpairs; i++) {
        connfd = ::accept(sockfd, NULL, 0);
        if (connfd < 0) 
            throw std::runtime_error("Accept failed");
        
        // Read qpid
        if (::read(connfd, recv_buf, sizeof(uint32_t)) != sizeof(uint32_t)) {
            ::close(connfd);
            throw std::runtime_error("Could not read a remote qpid");
        }
        memcpy(&recv_qpid, recv_buf, sizeof(uint32_t));

        // Hash
        if(qpairs.find(recv_qpid) == qpairs.end()) {
            // Send nack
            ack = msgNAck;
            if (::write(connfd, &ack, 1) != 1)  {
                ::close(connfd);
                throw std::runtime_error("Could not send ack/nack");
            }

            throw std::runtime_error("Queue pair exchange failed, wrong qpid received");
        }

        // Send ack
        ack = msgAck;
        if (::write(connfd, &ack, 1) != 1)  {
            ::close(connfd);
            throw std::runtime_error("Could not send ack/nack");
        }

        // Read a queue
        if (::read(connfd, recv_buf, sizeof(ibvQ)) != sizeof(ibvQ)) {
            ::close(connfd);
            throw std::runtime_error("Could not read a remote queue");
        }

        ibvQpConn *ibv_qpair_conn = qpairs[recv_qpid].get();
        ibv_qpair_conn->setConnection(connfd);

        ibvQp *qpair = ibv_qpair_conn->getQpairStruct();
        memcpy(&qpair->remote, recv_buf, sizeof(ibvQ));
        DBG2("Qpair ID: " << recv_qpid);
        qpair->local.print("Local ");
        qpair->remote.print("Remote"); 

        // Send a queue
        if (::write(connfd, &qpair->local, sizeof(ibvQ)) != sizeof(ibvQ))  {
            ::close(connfd);
            throw std::runtime_error("Could not write a local queue");
        }

        // Write context and connection
        ibv_qpair_conn->writeContext(port);

        // ARP lookup
        ibv_qpair_conn->doArpLookup();
    }
}

void ibvQpMap::exchangeQpSlave(const char *trgt_addr, uint16_t port) {
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

    DBG2("Slave side exchange started ...");

    if (asprintf(&service, "%d", port) < 0)
        throw std::runtime_error("asprintf() failed");

    n = getaddrinfo(trgt_addr, service, &hints, &res);
    if (n < 0) {
        free(service);
        throw std::runtime_error("getaddrinfo() failed");
    }

    int n_qpairs = qpairs.size();
    for(auto &[curr_qpid, curr_qp_conn] : qpairs) {
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
            throw std::runtime_error("Could not connect to master: " + std::string(trgt_addr) + ":" + to_string(port));

        // Send qpid
        if (::write(sockfd, &curr_qpid, sizeof(uint32_t)) != sizeof(uint32_t)) {
            ::close(sockfd);
            throw std::runtime_error("Could not write a qpid");
        }

        // Wait for ack
        if(::read(sockfd, recv_buf, 1) != 1) {
            ::close(sockfd);
            throw std::runtime_error("Could not read ack/nack");
        }
        memcpy(&ack, recv_buf, 1);
        if(ack != msgAck) 
            throw std::runtime_error("Received nack");

        // Send a queue
        if (::write(sockfd, &curr_qp_conn->getQpairStruct()->local, sizeof(ibvQ)) != sizeof(ibvQ)) {
            ::close(sockfd);
            throw std::runtime_error("Could not write a local queue");
        }

        // Read a queue
        if(::read(sockfd, recv_buf, sizeof(ibvQ)) != sizeof(ibvQ)) {
            ::close(sockfd);
            throw std::runtime_error("Could not read a remote queue");
        }

        curr_qp_conn->setConnection(sockfd);

        ibvQp *qpair = curr_qp_conn->getQpairStruct();
        memcpy(&qpair->remote, recv_buf, sizeof(ibvQ));
        DBG2("Qpair ID: " << curr_qpid);
        qpair->local.print("Local ");
        qpair->remote.print("Remote");

        // Write context and connection
        curr_qp_conn->writeContext(port);

        // ARP lookup
        curr_qp_conn->doArpLookup();

        if (res) 
            freeaddrinfo(res);
        free(service);
    }
}

}