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
// Communication lib
// ======-------------------------------------------------------------------------------

template <typename Cmpl, typename... Args>
class cLib {
private:
    int sockfd;
    struct sockaddr_un server;
    char recv_buff[recvBuffSize];

    static std::atomic_uint32_t curr_id;

public:
    cLib(const char *sock_name, int32_t fid) {
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

        if(write(sockfd, &fid, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }
        std::cout << "Client registered" << std::endl;
    }

    ~cLib() {
        // Send request
        int32_t req[3];
        req[0] = defOpClose;

        // Close conn
        if(write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }
        std::cout << "Sent close" << std::endl;

        close(sockfd);
    }

    // Server comm
    Cmpl task(int32_t priority, Args... msg) {
        // Send request
        int32_t req[3];
        req[0] = defOpTask;
        req[1] = curr_id++;
        req[2] = priority;
        
        // Send tid and opcode
        if(write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            std::cout << "ERR:  Failed to send a request" << std::endl;
            exit(EXIT_FAILURE);
        }

        // Send payload
        auto f_wr = [&](auto& x){
            using U = decltype(x);
            int size_arg = sizeof(U);

            if(write(sockfd, &x, size_arg) != size_arg) {
                std::cout << "ERR:  Failed to send a request" << std::endl;
                exit(EXIT_FAILURE);
            }
        };
        (f_wr(msg), ...);
        //std::apply([=](auto&&... args) {(f_wr(args), ...);}, msg);
        std::cout << "Sent payload" << std::endl;

        // Wait for completion
        int32_t cmpl_tid;
        Cmpl cmpl_ev;

        if(read(sockfd, recv_buff, sizeof(int32_t)) != sizeof(int32_t)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_tid, recv_buff, sizeof(int32_t));

        if(read(sockfd, recv_buff, sizeof(Cmpl)) != sizeof(Cmpl)) {
            std::cout << "ERR:  Failed to receive completion event" << std::endl;
            exit(EXIT_FAILURE);
        }
        memcpy(&cmpl_ev, recv_buff, sizeof(Cmpl));

        std::cout << "Received completion" << std::endl;
        
        return cmpl_ev;
    }
};

template <typename Cmpl, typename... Args>
std::atomic<uint32_t> cLib<Cmpl, Args...>::curr_id;

}

// Operations