/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_CSERVICE_HPP_
#define _COYOTE_CSERVICE_HPP_

#include <map>
#include <mutex>
#include <vector>
#include <string>
#include <signal.h>
#include <unistd.h>
#include <sys/un.h>
#include <syslog.h>
#include <sys/stat.h>

#include <coyote/cFunc.hpp>
#include <coyote/cSched.hpp>
#include <coyote/cThread.hpp>

namespace coyote {

/** 
 * @brief Coyote background service
 * 
 * This class implements the Coyote background service which 
 * runs on server node and can execute pre-defined Coyote functions.
 * On the client side, the users can connect to this service
 * through the helper class cConn and submit requests to the loaded 
 * functions. The service will automatically reconfigure the vFPGA
 * with the correct bistream. The requests can be local or remote.
 * 
 * @note There is currently a bug in terminating the signals. Since the signal handler
 * is static and limited in parameters, is it not aware of what instance should be terminated.
 * Therefore, for now, the signal handler terminates all instances of the service. Users should
 * only terminate the service once all vFPGAs have finished processing requests.
 *
 * TODO:
 *  - Remote connections
 */
class cService {

private: 

    /** 
     * @brief Instances of the services
     *
     * We only allow one instance of the service per vFPGA on a single device, 
     * to ensure that mutliple services do not run in parallel on the same vFPGA,
     * which can lead to multiple reconfigurations, execution conflicts etc.
     * The map of the key is the device ID concatenated with the vFPGA ID.
     */
    static std::map<std::string, cService*> services;

    /// Unique service ID, derived from the name
    std::string service_id;

    /// Name of the socket for communication
    std::string socket_name; 

    /// Boolean flag indicating whether the service is running; prevents double-starting daemon
    bool is_running;

    /// Socket file descriptor for communication
    int sockfd;

    /// Whether the service receives requests from a remote node or locally
    bool remote;

    /// vFPGA ID associated with the service
    int32_t vfid;

    /// Device number, for systems with multiple vFPGAs
    uint32_t device;

    /// Port for remote connections
    uint16_t port;

    /// A map of the connected clients and their corresponding Coyote threads which are used for executing the functions
    std::map<int, std::unique_ptr<cThread>> coyote_threads;

    /// Dedicated threads which process the requests for each connected client; one for incoming request and one for writing the result back
    std::map<int, std::pair<std::thread, std::thread>> connection_threads;

    /// Scheduler instance; handles the execution of tasks as well as reconfiguration, where required
    cSched *scheduler;
    
    /// An atomic variable; used for generating unique IDs for tasks on the server side
    std::atomic<int32_t> task_counter;

    /**
     * @brief A map of client-submitted tasks
     * When a client submits a task, it holds an ID which is written back with the task result, 
     * so that the client can link the result to the task (see cConn::checkCompletedTasks() for details). 
     * However, there is no guarantee that the client-submitted task ID is globally unique (because of multiple clients), 
     * so for each task, the cService also stores a server-generated task ID.
     */
    std::map<int, std::vector<std::pair<int32_t, int32_t>>> tasks;

    /** @brief Task map locks
     * Since the map is written by the processRequests() thread and read by the  
     * sendResponses() thread, thread safety must be ensured when accesing the map.
     */
    std::map<int, std::unique_ptr<std::mutex>> task_locks;

    /// A list of connection to be cleaned up; if the bool value is true, the connection is stale and should be cleaned up; false indicated it's been cleaned up
    std::map<int, bool> conns_to_clean;

    /// Dedicated thread that periodically iterates conns_to_clean and release stale connection threads and resources
    std::thread cleanup_thread;

    /// A boolean flag indicating whether the clean-up thread is running
    bool run_cleanup_thread;

    /// Default constructor; private to ensure the class is implemented as a singleton
    cService(std::string name, bool remote, int32_t vfid, uint32_t device, bool reorder, uint16_t port);

    /**
     * @brief Handles signals sent to the background service
     *
     * @note Currently only SIGTERM is handled, which is used to gracefully
     * terminate the service and clean up resources. Other signals are ignored.
     */
    void daemonSigHandler(int signum);

    /// Just a wrapper around daemonSigHandler; since the handler must be static
    static void sigHandler(int signum);

    /// Initializes the background daemon for this service
    void initDaemon();

    /// Initializes the socket for connections to this service, either local or remote
    void initSocket();

    /// Function that periodically iterates and releases resources (e.g., threads) held by stale connections
    void cleanConns();

    /// Accepts a local connection (IPC) to this service
    void acceptConnectionLocal();

    /// Accepts a connection from a remote client to this service
    void acceptConnectionRemote();

    /**
     * @brief Processes client requests in a dedicated thread
     *
     * This function continuously loops to accept incoming requests
     * for a connected client. It stores the requests in a list and
     * can close the connection if the client sends a close request.
     *
     * @param connfd The connection file descriptor for the client
     */
    void processRequests(int connfd);

    /**
     * @brief Send client responses in a dedicated thread
     *
     * This function continuously loops to check whether a client task
     * has been completed and sends the response back to the client.
     *
     * @param connfd The connection file descriptor for the client
     */
    void sendResponses(int connfd);

public:

    /**
     * @brief Creates an instance of the service for a vFPGA
     *
     * If an instance already exists, return the existing instance ("singleton" implementation)
     *
     * @param name Unique name for the service
     * @param remote Local or remote service
     * @param vfid Virtual FPGA ID associated with the service
     * @param device Device number, for systems with multiple vFPGAs 
     * @param reorder Allow the scheduler to reorder tasks, to minimize reconfigurations
     * @param port Port for remote connections
     */
    static cService* getInstance(std::string name, bool remote, int32_t vfid, uint32_t device = 0, bool reorder = true, uint16_t port = DEF_PORT) {
        std::string tmp_id = std::to_string(device) + "-" + std::to_string(vfid);
        
        if (services.find(tmp_id) != services.end()) {
            if (services[tmp_id] == nullptr) {
               services[tmp_id] = new cService(name, remote, vfid, device, reorder, port);
            }
        } else {
            services[tmp_id] = new cService(name, remote, vfid, device, reorder, port);
        }

        return services[tmp_id];

    }

    /**
     * @brief Starts the service
     *
     * This function initializes the daemon, sets up the socket for communication,
     * and starts the scheduler thread to handle incoming requests.
     * It will also accept connections from clients and register them.
     */
    void start();

    /**
    * @brief Adds an arbitrary user function to the service
    * 
    * @param fn Unique pointer to the bFunc object representing the function
    * @return 0 if the function was added successfully, 1 if bitstream cannot be opened, 2 if the function ID already exists 
    *
    * @note Implemented in the header file since it is a templated function
    */
    int addFunction(std::unique_ptr<bFunc> fn) {
        return scheduler->addFunction(std::move(fn));
    }

};

}

#endif // _COYOTE_CSERVICE_HPP_
