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

#include "cThread.hpp"

using namespace std;

constexpr auto const sleepIntervalDaemon = 5000L;
constexpr auto const sleepIntervalRequests = 500L;
constexpr auto const sleepIntervalCompletion = 200L;
constexpr auto const aesOpId = 0;
constexpr auto const opPrio = 0;
constexpr auto const maxNumClients = 64;

namespace fpga {

static void sig_handler(int signum);

// Service threads
class serviceThread {
private:
    bool run = false;
    thread t;

public:
    serviceThread(void (*f)()) {
        run = true;
        t = thread(f);
    }

    ~serviceThread() {
        run = false;
        t.join();
    }

    bool isRunning() const { return run; }
};

// Service
class cService {
private: 
    // Forks
    static pid_t pid;

    // ID
    int32_t vfid;
    string service_id;

    // Threads
    serviceThread *thread_req;
    serviceThread *thread_rsp;

    // Conn
    int sockfd;
    int curr_id = { 0 };
    unordered_map<int, std::unique_ptr<cThread>> clients;
    mutex mtx_cli;

    void daemon_init();
    void socket_init();
    void threads_init();

public:
    
    void cService (int32_t vfid);
    
    void accept_connection();

};


}