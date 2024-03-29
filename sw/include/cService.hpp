#pragma once

#include <dirent.h>
#include <iterator>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <iostream>
#include <stdlib.h>
#include <string>
#include <sys/stat.h>
#include <syslog.h>
#include <unistd.h>
#include <vector>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <iomanip>
#include <chrono>
#include <thread>
#include <limits>
#include <assert.h>
#include <stdio.h>
#include <sys/un.h>
#include <errno.h>
#include <wait.h>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <condition_variable>
#include <any>

#include "cSched.hpp"
#include "bFunc.hpp"
#include "cThread.hpp"

using namespace std;

namespace fpga {

/**
 * @brief Coyote service
 * 
 * Coyote daemon, provides background scheduling service.
 * 
 */
class cService : public cSched {
protected:
    // Singleton
    static cService *cservice;

    // Function map
    std::unordered_map<int32_t, std::unique_ptr<bFunc>> functions;

    // Forks
    pid_t pid;

    // ID
    int32_t vfid = { -1 };
    csDev dev;
    string service_id;

    // Type
    bool remote = { false };
    uint16_t port;

    // Conn
    string socket_name;
    int sockfd;
    int curr_id = { 0 };

    // Notify 
    void (*uisr)(int);

    /**
     * @brief class handler
    */
   static void sigHandler(int signum);
   void myHandler(int signum);

    /**
     * @brief Initialize
     * 
     */
    void daemonInit();
    void socketInit();

    /**
     * @brief Accept connections
    */
    void acceptConnectionLocal();
    void acceptConnectionRemote();

    /**
     * @brief Constructor (protected - singleton)
    */
    cService(string name, bool remote, int32_t vfid, csDev dev, void (*uisr)(int) = nullptr, uint16_t port = defPort, bool priority = true, bool reorder = true);    

public:

    /**
     * @brief Creates a service for a single vFPGA
     * 
     * @param vfid - vVFPGA id
     * @param dev - PCIe device
     * @param priority - priority ordering
     * @param reorder - reordeing of tasks
     */

    static cService* getInstance(string name, bool remote, int32_t vfid, csDev dev, void (*uisr)(int) = nullptr, uint16_t port = defPort, bool priority = true, bool reorder = true) {
        if(cservice == nullptr) 
            cservice = new cService(name, remote, vfid, dev, uisr, port, priority, reorder);
        return cservice;
    }

    /**
     * @brief Main run service
     * 
     */
    void start();

    /**
     * @brief Add an arbitrary user function
     * 
     */
    void addFunction(int32_t fid, std::unique_ptr<bFunc> f);

    /**
     * @brief QP exchange util (blocking)
     * 
     */
    static void exchangeQpClient() {}
    static void exchangeQpServer() {}
};


}       
