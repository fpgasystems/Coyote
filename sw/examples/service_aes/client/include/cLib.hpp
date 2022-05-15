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

#include "cIpc.hpp"
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
    void run(msgType msg);
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
    opcode = opCodeClose;
    if(write(sockfd, &opcode, sizeof(uint8_t)) != sizeof(uint8_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    close(sockfd);
}

void cLib::run(msgType msg) {
    // Send request
    opcode = opCodeRun;
    if(write(sockfd, &opcode, sizeof(uint8_t)) != sizeof(uint8_t)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    std::cout << "Sent opcode" << std::endl;

    // Send payload
    if(write(sockfd, &msg, sizeof(msgType)) != sizeof(msgType)) {
        std::cout << "ERR:  Failed to send a request" << std::endl;
        exit(EXIT_FAILURE);
    }

    std::cout << "Sent payload" << std::endl;

    // Wait for completion
    int32_t tid;

    if(read(sockfd, recv_buff, sizeof(int32_t)) != sizeof(int32_t)) {
        std::cout << "ERR:  Failed to receive completion event" << std::endl;
        exit(EXIT_FAILURE);
    }
    memcpy(&tid, recv_buff, sizeof(int32_t));

    std::cout << "Received completion event, tid: " << tid << std::endl;
}

// Operations