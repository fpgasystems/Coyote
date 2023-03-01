#pragma once

#include "cDefs.hpp"

#include <iostream>
#include <string>
#include <malloc.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <fstream>
#include <fcntl.h>
#include <unistd.h>
#include <iomanip>
#include <x86intrin.h>
#include <boost/program_options.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <sstream>
#include <atomic>
#include <vector>

namespace fpga {

// ======-------------------------------------------------------------------------------
// Args wrapper
// ======-------------------------------------------------------------------------------
class cMsg {
protected:
    static std::atomic<int32_t> curr_tid;
public:
    int32_t tid;
    int32_t oid;
    std::vector<uint64_t> args;

    cMsg(int32_t oid, std::vector<uint64_t> args) :
        tid(curr_tid++), oid(oid), args(args) {}

    inline auto getTid() { return tid; }
    inline auto getOid() { return oid; }
    inline auto getArgs() { return args.data(); }
    inline auto getArgsSize() { return args.size(); }
};

std::atomic<int32_t> cMsg::curr_tid;

// ======-------------------------------------------------------------------------------
// Communication lib
// ======-------------------------------------------------------------------------------

class cLib {
private:
    int sockfd;
    struct sockaddr_un server;
    uint8_t opcode;
    char recv_buff[recvBuffSize];

    static std::atomic_uint32_t curr_id;

public:
    cLib(const char *sock_name);
    ~cLib();

    // Server comm
    int32_t task(cMsg msg);
};

std::atomic<uint32_t> cLib::curr_id;

cLib::cLib(const char *sock_name) {
    // Open a socket
    if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        std::cout << "ERR:  Failed to create a server socket" << std::endl;
        exit(EXIT_FAILURE);
    }

    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, sock_name);

    if(connect(sockfd, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
        close(sockfd);
        std::cout << "ERR:  Failed to connect to a server socket" << std::endl;
        exit(EXIT_FAILURE);
    }

    // Register
    pid_t pid = getpid();
    if(write(sockfd, &pid, sizeof(pid_t)) != sizeof(pid_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    std::cout << "Sent pid" << std::endl;
}

cLib::~cLib() {
    // Close conn
    opcode = defOpClose;
    if(write(sockfd, &opcode, sizeof(int32_t)) != sizeof(int32_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    std::cout << "Sent close" << std::endl;

    close(sockfd);
}

int32_t cLib::task(cMsg msg) {
    // Send request
    int32_t req[2];
    req[0] = msg.getTid();
    req[1] = msg.getOid();

    // Send tid and opcode
    if(write(sockfd, &req, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }
    
    // Send payload size
    int32_t msg_size = msg.getArgsSize() * sizeof(uint64_t);

    if(write(sockfd, &msg_size, sizeof(int32_t)) != sizeof(int32_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    // Send payload
    if(write(sockfd, msg.getArgs(), msg_size) != msg_size) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }
    std::cout << "Sent payload" << std::endl;

    // Wait for completion
    int32_t cmpl[2];

    if(read(sockfd, recv_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
        std::cout << "ERR:  Failed to receive completion event" << std::endl;
        exit(EXIT_FAILURE);
    }
    memcpy(&cmpl, recv_buff, 2 * sizeof(int32_t));

    std::cout << "Received completion event, tid: " << cmpl[0] << std::endl;
    return cmpl[1];
}

}

// Operations