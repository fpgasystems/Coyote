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

#include "cIpc.hpp"
#include "cThread.hpp"

constexpr auto const sleepIntervalDaemon = 5000L;
constexpr auto const sleepIntervalRequests = 500L;
constexpr auto const sleepIntervalCompletion = 200L;
constexpr auto const aesOpId = 0;
constexpr auto const opPrio = 0;
constexpr auto const maxNumClients = 64;
static pid_t pid;

using namespace std;
using namespace fpga;

static void sig_handler(int signum);

void daemon_init();
void socket_init();
void threads_init();

void accept_connection();

// Threads
class threadType {
private:
    bool run = false;
    thread t;

public:
    threadType(void (*f)()) {
        run = true;
        t = thread(f);
    }

    ~threadType() {
        run = false;
        t.join();
    }

    bool isRunning() const { return run; }
};

// Globals
struct connType {
    unordered_map<int, std::unique_ptr<cThread>> users;
    mutex mtx;
};
connType connections;

int sockfd;
int curr_id = 0;

threadType *thread_req;
threadType *thread_rsp;

/**
 * @brief Main
 *  
 */
int main(void) 
{   
    // Init daemon
    daemon_init();

    // Init socket
    socket_init();

    // Start threads
    threads_init();

    // Main
    while(1) {
        accept_connection();
    }
}

// Inits
static void sig_handler(int signum)
{   
    if(signum == SIGTERM) {
        syslog(LOG_NOTICE, "SIGTERM sent to %d\n", (int)pid);
        unlink(socketName);

        delete thread_req;
        //delete thread_rsp;
        //delete csched;

        kill(pid, SIGTERM);
        syslog(LOG_NOTICE, "Exiting");
        closelog();
        exit(EXIT_SUCCESS);
    } else {
        syslog(LOG_NOTICE, "Signal %d not handled", signum);
    }
}

/**
 * @brief Initialize the service
 * 
 */
void daemon_init()
{
    // Fork
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Sid
    if(setsid() < 0) 
        exit(EXIT_FAILURE);

    // Signal handler
    signal(SIGTERM, sig_handler);
    signal(SIGCHLD, SIG_IGN);
    signal(SIGHUP, SIG_IGN);

    // Fork
    pid = fork();
    if(pid < 0 ) 
        exit(EXIT_FAILURE);
    if(pid > 0 ) 
        exit(EXIT_SUCCESS);

    // Permissions
    umask(0);

    // Cd
    if((chdir("/")) < 0) {
        exit(EXIT_FAILURE);
    }

    // Syslog
    openlog("coyote-daemon", LOG_NOWAIT | LOG_PID, LOG_USER);
    syslog(LOG_NOTICE, "Successfully started coyote-daemon");

    // Close fd
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
}

/**
 * @brief Socket init
 * 
 */
void socket_init()
{
    syslog(LOG_NOTICE, "Socket initialization");

    sockfd = -1;
    struct sockaddr_un server;
    socklen_t len;

    if((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        syslog(LOG_ERR, "Error creating a server socket");
        exit(EXIT_FAILURE);
    }

    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, socketName);
    unlink(server.sun_path);
    len = strlen(server.sun_path) + sizeof(server.sun_family);
    
    if(bind(sockfd, (struct sockaddr *)&server, len) == -1) {
        syslog(LOG_ERR, "Error bind()");
        exit(EXIT_FAILURE);
    }

    if(listen(sockfd, maxNumClients) == -1) {
        syslog(LOG_ERR, "Error listen()");
        exit(EXIT_FAILURE);
    }
}

/**
 * @brief THREADS
 * 
 */

//
// AES en(de)cryption task
//
auto aes = [](cProc* cproc, msgType msg) {
    syslog(LOG_NOTICE, "Task started, pid: %d", cproc->getPid());
    
    // User map
    cproc->userMap((void*)msg.src, msg.len);

    // Lock
    cproc->pLock();

    // Key load
    cproc->setCSR(msg.key_low, keyLowReg);
    cproc->setCSR(msg.key_high, keyHighReg);
    cproc->setCSR(keyProp, keyCtrlReg);
    
    // En(de)crypt
    cproc->invoke({CoyoteOper::TRANSFER, (void*)msg.src, msg.len});

    // Unlock
    cproc->pUnlock();

    syslog(LOG_NOTICE, "Task ended, pid: %d", cproc->getPid());
};

void process_requests()
{
    char recv_buf[recvBuffSize];
    memset(recv_buf, 0, recvBuffSize);
    msgType msg;
    uint8_t ack_msg;
    int n;

    while(thread_req->isRunning()) {
        connections.mtx.lock();

        for (auto & el : connections.users) {
            int connfd = el.first;
            if(read(connfd, recv_buf, 1) == 1) {
                
                uint8_t opcode = uint8_t(recv_buf[0]);
                syslog(LOG_ERR, "opCode: %d", opcode);

                switch (opcode) {

                // Run the operator
                case opCodeRun:
                    if(n = read(connfd, recv_buf, sizeof(msgType)) == sizeof(msgType)) {
                        memcpy(&msg, recv_buf, sizeof(msgType));
                        syslog(LOG_NOTICE, "Received new request, connfd: %d, tid: %d, src: %lx, len: %d, key_low: %lx, key_high: %lx",
                            el.first, msg.tid, msg.src, msg.len, msg.key_low, msg.key_high);

                        // Schedule
                        el.second->scheduleTask(std::unique_ptr<bTask>(new cTask(msg.tid, aesOpId, opPrio, aes, msg)));
                    } else {
                        syslog(LOG_ERR, "Request invalid, connfd: %d, received: %d", connfd, n);
                    }
                    break;

                // Close connection
                case opCodeClose:
                    syslog(LOG_NOTICE, "Received close connection request, connfd: %d", connfd);
                    close(connfd);
                    connections.users.erase(el.first);
                    break;
                
                default:
                    break;
                }
            }
        }

        connections.mtx.unlock();
        nanosleep((const struct timespec[]){{0, sleepIntervalRequests}}, NULL);
    }
}

void process_responses()
{
    int n;
    int ack_msg;
    
    while(thread_rsp->isRunning()) {

        for (auto & el : connections.users) {
            int32_t tid = el.second->getCompletedNext();
            if(tid != -1) {
                syslog(LOG_NOTICE, "Running here...");
                int connfd = el.first;

                if(write(connfd, &tid, sizeof(int32_t)) == sizeof(int32_t)) {
                    syslog(LOG_NOTICE, "Sent completion, connfd: %d, tid: %d", connfd, tid);
                } else {
                    syslog(LOG_ERR, "Completion could not be sent, connfd: %d", connfd);
                }
            }
        }

        nanosleep((const struct timespec[]){{0, sleepIntervalCompletion}}, NULL);
    }
}

void threads_init() 
{
    syslog(LOG_NOTICE, "Thread initialization");

    thread_req = new threadType(&process_requests);
    thread_rsp = new threadType(&process_responses);
}

// Accept conn
void accept_connection()
{
    sockaddr_un client;
    socklen_t len = sizeof(client); 
    int connfd;
    char recv_buf[recvBuffSize];
    int n;

    if((connfd = accept(sockfd, (struct sockaddr *)&client, &len)) == -1) {
        syslog(LOG_NOTICE, "No new connections");
    } else {
        syslog(LOG_NOTICE, "Connection accepted, connfd: %d", connfd);

        pid_t pid;
        if(n = read(connfd, recv_buf, sizeof(pid_t)) == sizeof(pid_t)) {
            memcpy(&pid, recv_buf, sizeof(pid_t));
            syslog(LOG_NOTICE, "Registered pid: %d", pid);
        } else {
            syslog(LOG_ERR, "Registration failed, connfd: %d, received: %d", connfd, n);
        }

        connections.mtx.lock();
        
        if(connections.users.find(connfd) == connections.users.end()) {
            syslog(LOG_NOTICE, "Connection inserting");
            connections.users.insert({connfd, std::make_unique<cThread>(targetRegion, pid)});
            syslog(LOG_NOTICE, "Connection inserted");
        }

        connections.mtx.unlock();
    }

    nanosleep((const struct timespec[]){{0, sleepIntervalDaemon}}, NULL);
}

