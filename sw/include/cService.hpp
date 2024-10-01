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

// Can use Scheduler, cFunc and cThread
#include "cSched.hpp"
#include "bFunc.hpp"
#include "cThread.hpp"

using namespace std;

namespace fpga {

/**
 * @brief Coyote service
 * 
 * Coyote daemon, provides background scheduling service.
 * Inherits from cSched (not sure why though)
 * 
 */
class cService : public cSched {
protected:
    // Singleton: Important that there's only a single instance of cService per vFPGA that controls all threads registered for this vFPGA
    static cService *cservice;

    // Function map - can store client threads for the calling function-IDs
    std::unordered_map<int32_t, std::unique_ptr<bFunc>> functions;

    // Forks
    pid_t pid;

    // ID - targets a single vFPGA & dev, thus these are global variables / identifiers
    int32_t vfid = { -1 };
    uint32_t dev;
    string service_id;

    // Type - remote connection 
    bool remote = { false };
    uint16_t port;

    // Conn - connection via a socket, uniquely identified via curr_id
    string socket_name;
    int sockfd;
    int curr_id = { 0 };

    // Notify - pointer to user interrupt service routine 
    void (*uisr)(int);

    /**
     * @brief class handler
    */
   static void sigHandler(int signum);
   void myHandler(int signum);

    /**
     * @brief Initializer for daemon and socket (for connection)
     * 
     */
    void daemonInit();
    void socketInit();

    /**
     * @brief Accept connections - methods for (QP?) exchange with local and remote 
    */
    void acceptConnectionLocal();
    void acceptConnectionRemote();

    /**
     * @brief Constructor (protected - singleton)
    */
    cService(string name, bool remote, int32_t vfid, uint32_t dev, void (*uisr)(int) = nullptr, uint16_t port = defPort, bool priority = true, bool reorder = true);    

public:

    /**
     * @brief Creates a service for a single vFPGA - execute the protected constructor internally to keep the singleton-property 
     * 
     * @param vfid - vFPGA id
     * @param dev - PCIe device
     * @param priority - priority ordering
     * @param reorder - reordeing of tasks
     */

    static cService* getInstance(string name, bool remote, int32_t vfid, uint32_t dev, void (*uisr)(int) = nullptr, uint16_t port = defPort, bool priority = true, bool reorder = true) {
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
     * @brief QP exchange util (blocking) - used on the server side, while the client side forces active exchange via the constructor in cLib
     * 
     */
    static void exchangeQpClient() {}
    static void exchangeQpServer() {}
};


}       
