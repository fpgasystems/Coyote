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

#include <coyote/cService.hpp>

namespace coyote {

std::map<std::string, cService*> coyote::cService::services;

cService::cService(std::string name, bool remote, int32_t vfid, uint32_t device, bool reorder, uint16_t port):
    remote(remote), vfid(vfid), device(device), port(port), is_running(false) {
    service_id = ("coyote-daemon-dev-" + std::to_string(device) + "-vfid-" + std::to_string(vfid) + "-" + name).c_str();
    socket_name = ("/tmp/" + service_id).c_str();
    sockfd = -1;
    task_counter = 0;
    scheduler = cSched::getInstance(vfid, device, reorder);
}

void cService::sigHandler(int signum) {
    for (auto &[key, cservice] : services) {
        if (cservice != nullptr) {
            cservice->daemonSigHandler(signum);
            delete cservice;
            cservice = nullptr;
            syslog(LOG_NOTICE, "Released service %s memory", key.c_str());
        }
    }
    exit(EXIT_SUCCESS);
}

void cService::daemonSigHandler(int signum) {
    // Handle termination signals; cleanup resources and stop active threads
    if (signum == SIGTERM || signum == SIGKILL) {
        syslog(LOG_NOTICE, "SIGTERM received, exiting...\n");

        scheduler->stop();

        // TODO: Do we need to add active connection to conns_to_clean?
        run_cleanup_thread = false;
        if (cleanup_thread.joinable()) {
            cleanup_thread.join();
        }

        unlink(socket_name.c_str());
        closelog();
        syslog(LOG_NOTICE, "Daemon %s terminated", service_id.c_str());
    // And ignore others...
    } else {
        syslog(LOG_NOTICE, "Signal %d not handled, ignoring", signum);
    }   
}

void cService::initDaemon() {
    // Fork = Create a new child process
    pid_t pid = fork();
    if (pid < 0) { exit(EXIT_FAILURE); }
    if (pid > 0) { exit(EXIT_SUCCESS); }
    if (setsid() < 0) { exit(EXIT_FAILURE); }

    // SIGTERM handler
    signal(SIGTERM, cService::sigHandler);
    
    // Ignore the SIGCHLD command to prevent the creation of zombie processes 
    signal(SIGCHLD, SIG_IGN); 

    // Ignore the SIGHUP command so that the process keeps running even if the terminal is killed
    signal(SIGHUP, SIG_IGN); 

    // Fork again; the new process is not a session leader and has no controlling terminal 
    pid = fork();
    if (pid < 0) { exit(EXIT_FAILURE); }
    if (pid > 0) { exit(EXIT_SUCCESS); }
    if (setsid() < 0) { exit(EXIT_FAILURE); }

    // Permissions - the daemon can read and write files with any required permission 
    umask(0);

    if ((chdir("/")) < 0) { exit(EXIT_FAILURE); }

    // Set-up syslog
    openlog(service_id.c_str(), LOG_NOWAIT | LOG_PID, LOG_USER);
    syslog(LOG_NOTICE, "Successfully started daemon %s", service_id.c_str());

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
}

void cService::initSocket() {
    if (remote) {
        syslog(LOG_NOTICE, "Initializating socket for remote connections");

        // Create the socket and check if it's successful
        sockfd = ::socket(AF_INET, SOCK_STREAM, 0);
        if (sockfd == -1) {
            syslog(LOG_ERR, "Error creating server socket");
            exit(EXIT_FAILURE);
        }

        // Bind the socket to any IP of the node and the target port
        struct sockaddr_in server;
        server.sin_family = AF_INET;
        server.sin_addr.s_addr = INADDR_ANY;
        server.sin_port = htons(port);
        if (::bind(sockfd, (struct sockaddr*) &server, sizeof(server)) < 0) {
            syslog(LOG_ERR, "Error binding socket");
            exit(EXIT_FAILURE);
        }

        if (sockfd < 0) {
            syslog(LOG_ERR, "Error listening to port socket %d", port);
            exit(EXIT_FAILURE);
        }

    } else {
        syslog(LOG_NOTICE, "Initializating socket for local connections");

        // Create a local socket for IPC and check success
        if ((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
            syslog(LOG_ERR, "Error creating server socket");
            exit(EXIT_FAILURE);
        }

        // Bind the socket
        struct sockaddr_un server;
        server.sun_family = AF_UNIX;
        strcpy(server.sun_path, socket_name.c_str());
        unlink(server.sun_path);
        socklen_t len = strlen(server.sun_path) + sizeof(server.sun_family);
        if (bind(sockfd, (struct sockaddr *) &server, len) == -1) {
            syslog(LOG_ERR, "Error binding socket");
            exit(EXIT_FAILURE);
        }
    }

    // Try to listen to the socket 
    if (listen(sockfd, MAX_NUM_CLIENTS) == -1) {
        syslog(LOG_ERR, "Error listening on socket");
        exit(EXIT_FAILURE);
    }

    syslog(LOG_NOTICE, "Socket initialized");

}

void cService::cleanConns() {
    syslog(LOG_NOTICE, "Starting cleanConns thread");

    while (run_cleanup_thread) {
        // Iterate over the connection and release the ones that are stale
        auto tmp = conns_to_clean.begin();
        while (tmp != conns_to_clean.end()) {
            int connfd = (*tmp).first;
            bool is_stale = (*tmp).second;

            if (is_stale) {
                syslog(LOG_NOTICE, "Releasing resources for connection %d", connfd);
                // Join the thread for processing requests and sending responses
                if (connection_threads.find(connfd) != connection_threads.end()) {
                    if (connection_threads[connfd].first.joinable()) {
                        connection_threads[connfd].first.join();
                    }
                    if (connection_threads[connfd].second.joinable()) {
                        connection_threads[connfd].second.join();
                    }
                    connection_threads.erase(connfd);
                }
                
                // Release the Coyote thread
                if (coyote_threads.find(connfd) != coyote_threads.end()) {
                    coyote_threads.erase(connfd);
                }

                // Delete the task entry and the corresponding lock associated to this client
                if (tasks.find(connfd) != tasks.end()) {
                    tasks.erase(connfd);
                }

                if (task_locks.find(connfd) != task_locks.end()) {
                    task_locks.erase(connfd);
                }

                // Delete the is_stale entry for this confd; done in case there are future connections with the same connfd value. 
                // See acceptConnectionLocal() function for an explanation when this could happen.
                tmp = conns_to_clean.erase(tmp);
                syslog(LOG_NOTICE, "Resources released");

                if (tmp != conns_to_clean.end()) {
                    tmp++;
                }
            }
        }

        std::this_thread::sleep_for(std::chrono::microseconds(DAEMON_CLEAN_CONNS_SLEEP));
    }
}

void cService::processRequests(int connfd) {
    bool running = true;
    syslog(LOG_NOTICE, "Starting connection thread for client with connfd %d", connfd);

    while (running) {
        char recv_buf[RECV_BUFF_SIZE];
        if (read(connfd, recv_buf, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t)) {
            // Read opcode (DEF_OP_CLOSE_CONN or DEF_OP_SUBMIT_TASK)
            int32_t request[3];
            memcpy(&request, recv_buf, 3 * sizeof(int32_t));
            int32_t opcode = request[0];

            switch (opcode) {
                case DEF_OP_CLOSE_CONN: {
                    syslog(LOG_NOTICE, "Received close connection request for client with connfd %d", connfd);
                    close(connfd);
                    running = false;
                    break;
                }

                case DEF_OP_SUBMIT_TASK: {
                    // Read function and task ID; check if the function ID has been registered with the service; 
                    // If not, return appropriate (error) code and stop function execution
                    int32_t fid = request[1];
                    int32_t client_tid = request[2];
                    
                    // If the function is not found, stop execution
                    if (!scheduler->isFunctionRegistered(fid)) {
                        syslog(LOG_WARNING, "Client %d requested unkown function, fid: %d with client_tid: %d, stopping request...", connfd, fid, client_tid);
                        bool send_buff[RECV_BUFF_SIZE];
                        int32_t ret_code = 1;
                        memcpy(send_buff, &ret_code, sizeof(int32_t));
                        memcpy(send_buff + sizeof(int32_t), &client_tid, sizeof(int32_t));
                        if (write(connfd, &send_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
                            syslog(LOG_ERR, "Return code could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                        } 
                        break;
                    }
                    
                    // Otherwise, function is found and the task can be submitted to the scheduler
                    bFunc *requested_func = scheduler->getFunction(fid);
                    if (requested_func == nullptr) {
                        syslog(LOG_ERR, "UNEXPECTED BUG: Function with fid: %d marked as registered, but scheduler returned nullptr?!", fid);
                        continue;
                    }
                    syslog(LOG_NOTICE, "Client %d requested function fid: %d with client_tid: %d", connfd, fid, client_tid);

                    // Parse client arguments and store into a vector of char buffers; one for each function argument
                    int32_t ret_code = 0;
                    std::vector<std::vector<char>> arguments;     
                    std::vector<size_t> argument_sizes = requested_func->getArgumentSizes();

                    for (size_t &arg_size: argument_sizes) {
                        char recv_buff[RECV_BUFF_SIZE];
                        if (read(connfd, recv_buff, arg_size) == arg_size) {
                            std::vector<char> arg(recv_buff, recv_buff + arg_size);
                            arguments.emplace_back(arg);
                        } else {
                            // Failed to parse arguments; inform client and stop execution
                            syslog(LOG_WARNING, "Could not parse function arguments, fid: %d, connfd: %d, returning 1", fid, connfd);
                            bool send_buff[RECV_BUFF_SIZE];
                            ret_code = 1;
                            memcpy(send_buff, &ret_code, sizeof(int32_t));
                            memcpy(send_buff + sizeof(int32_t), &client_tid, sizeof(int32_t));
                            if (write(connfd, &send_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
                                syslog(LOG_ERR, "Return code could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                            }
                            break;
                        }
                    }

                    // If ret code is not zero, it means that the arguments could not be parsed; stop execution
                    if (ret_code) { break; }

                    // Check entries for this client connections exist --- they always should as they are created when client connects
                    // However, double check to avoid segmentation faults that can crash the server
                    if (tasks.find(connfd) == tasks.end() || task_locks.find(connfd) == task_locks.end()) {
                        syslog(LOG_ERR, "UNEXPECTED BUG: No task entry found in map for connfd: %d", connfd);
                        ret_code = 1;
                        bool send_buff[RECV_BUFF_SIZE];
                        memcpy(send_buff, &ret_code, sizeof(int32_t));
                        memcpy(send_buff + sizeof(int32_t), &client_tid, sizeof(int32_t));
                        if (write(connfd, &send_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
                            syslog(LOG_ERR, "Return code could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                        }
                        break;
                    }

                    // Create a new task and add it to the scheduler; if for some reason the task could not be added, return an error code to the client
                    int32_t server_tid = task_counter++;
                    task_locks[connfd]->lock();
                    tasks[connfd].emplace_back(client_tid, server_tid);
                    task_locks[connfd]->unlock();

                    std::unique_ptr<cTask> task = std::make_unique<cTask>(server_tid, fid,  requested_func->getReturnSize(), coyote_threads[connfd].get(), std::move(arguments));
                    bool task_added = scheduler->addTask(std::move(task));

                    if (!task_added) {
                        syslog(
                            LOG_ERR, 
                            "Could not add task with server_tid: %d, client_tid: %d, fid: %d, connfd: %d; most likely a server error; returning error code",
                            server_tid, client_tid, fid, connfd
                        );
                        bool send_buff[RECV_BUFF_SIZE];
                        ret_code = 1;
                        memcpy(send_buff, &ret_code, sizeof(int32_t));
                        memcpy(send_buff + sizeof(int32_t), &client_tid, sizeof(int32_t));
                        if (write(connfd, &send_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
                            syslog(LOG_ERR, "Return code could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                        }
                        break;
                    }

                    syslog(
                        LOG_NOTICE, 
                        "Added task with server_tid: %d, client_tid: %d, fid: %d, connfd: %d to scheduler queue",
                        server_tid, client_tid, fid, connfd
                    );
                    break;
                    
                }
                
                default: {
                    syslog(LOG_WARNING, "Received unknown request from client %d with opcode %d, ignoring...", connfd, opcode);
                    break;
                }
            }

        }

        std::this_thread::sleep_for(std::chrono::nanoseconds(DAEMON_PROCESS_REQUESTS_SLEEP));

    }

    conns_to_clean.emplace(connfd, true);
    syslog(LOG_NOTICE, "Connection %d closing ...", connfd);

}

void cService::sendResponses(int connfd) {
    syslog(LOG_NOTICE, "Starting response thread for client with connfd %d", connfd);
    bool run_response_thread = true;
    
    while (run_response_thread) {
        // Move sleep here instead of at the end; in case the following if skips this iteration
        std::this_thread::sleep_for(std::chrono::nanoseconds(DAEMON_PROCESS_REQUESTS_SLEEP));

        // For completness sake, check if there is an entry for this connection in the tasks map
        // However, this should always be the case, as the connection thread is started only after the entry is created
        bool entry_found = tasks.find(connfd) != tasks.end() && task_locks.find(connfd) != task_locks.end() ? true : false;
        if (!entry_found) {
            continue;
        }

        // Lock the mutex and iterate over the tasks for this connection
        task_locks[connfd]->lock();
        auto tmp = tasks[connfd].begin();
        while (tmp != tasks[connfd].end()) {
            int32_t client_tid = (*tmp).first;
            int32_t server_tid = (*tmp).second;
            
            if (scheduler->isTaskCompleted(server_tid)) {
                cTask *task = scheduler->getTask(server_tid);
                if (task == nullptr) {
                    syslog(LOG_ERR, "UNEXPECTED BUG: Task with server_tid: %d, connfd: %d marked as completed, but scheduler returned nullptr?!", server_tid, connfd);
                    continue;
                }
                
                // Function completed sucessfully, write success return code and task ID 
                bool send_buff[RECV_BUFF_SIZE];
                int32_t ret_code = 0;
                memcpy(send_buff, &ret_code, sizeof(int32_t));
                memcpy(send_buff + sizeof(int32_t), &client_tid, sizeof(int32_t));
                if (write(connfd, &send_buff, 2 * sizeof(int32_t)) != 2 * sizeof(int32_t)) {
                    syslog(LOG_ERR, "Return code could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                    break;
                }
                    
                size_t return_size = task->getRetValSize();
                if (write(connfd, task->getRetVal().data(), return_size) != return_size) {
                    syslog(LOG_ERR, "Return value could not be sent, connfd: %d, client_tid: %d", connfd, client_tid);
                }

                // Remove the task from the list to avoid sending the response again
                tmp = tasks[connfd].erase(tmp);
                syslog(LOG_NOTICE, "Sent response for task with server_tid: %d, client_tid: %d, connfd: %d", server_tid, client_tid, connfd);
            
            }

            if (tmp != tasks[connfd].end()) {
                tmp++;
            }
        }
        
        task_locks[connfd]->unlock();
        
        // If the connection has been marked for cleaning, stop the thread
        // A connection can be marked for cleaning has sent a disconnect request (DEF_OP_CLOSE_CONN in processRequests())
        if (conns_to_clean.find(connfd) != conns_to_clean.end()) {
            run_response_thread = !conns_to_clean[connfd];
        }
    }
}

void cService::acceptConnectionLocal() {
    sockaddr_un client_addr;
    socklen_t len = sizeof(client_addr); 
    int connfd;

    // Try to accept an incoming connection
    if ((connfd = accept(sockfd, (struct sockaddr *) &client_addr, &len)) != -1) {
    
        syslog(LOG_NOTICE, "Accepted local connection, connfd: %d", connfd);

        /**
         * The service often receives data from the clients (e.g., request opcode, function arguments etc.)
         * There is a clear sequence of steps, as implemented in processRequests() function, that the service
         * expects to receive from the client. If the client fails to send data or the correct arguments for the 
         * function, it can leave the server hanging. Therefore, set a timeout for the connection to prevent this.
         */
        if (setsockopt(connfd, SOL_SOCKET, SO_RCVTIMEO, &SERVER_RECV_TIMEOUT, sizeof(SERVER_RECV_TIMEOUT)) < 0) {
            syslog(LOG_WARNING, "Could not set timeout for connfd: %d", connfd);
        }

        // Read "remote" process ID of the client
        int n;
        pid_t rpid;
        char recv_buf[RECV_BUFF_SIZE];
        if ((n = read(connfd, recv_buf, sizeof(pid_t))) == sizeof(pid_t)) {
            memcpy(&rpid, recv_buf, sizeof(pid_t));
            syslog(LOG_NOTICE, "Registered pid: %d", rpid);

            /*
             * Set-up resources for this client and start the thread to process incodming requests
             * Each client is uniquely identified by its connection file descriptor (connfd);
             * At any given time, no two clients will have the same value of connfd
             * However, it's possible that a connfd with the same value is opened later (the cService has
             * no control over the connection file descriptors, they are assigned by the OS). Therefore, 
             * when a client disconnect, it's important to remove their resources. This is done by the
             * cleanConns() function, which periodically checks the conns_to_clean map and releases the resources.
             */ 
            task_locks.insert({connfd, std::make_unique<std::mutex>()});
            tasks.insert({connfd, std::vector<std::pair<int32_t, int32_t>>()});
            coyote_threads.insert({connfd, std::make_unique<cThread>(vfid, rpid, device)});
            connection_threads.insert({
                connfd, 
                std::make_pair<std::thread, std::thread>(                        
                    std::thread(&cService::processRequests, this, connfd),
                    std::thread(&cService::sendResponses, this, connfd)
                )
            });
            
        } else {
            ::close(connfd);
            syslog(LOG_WARNING, "Failed to register client, connfd: %d, received: %d", connfd, n);
        }

    }

    std::this_thread::sleep_for(std::chrono::microseconds(DAEMON_ACCEPT_CONN_SLEEP));
}

void cService::acceptConnectionRemote() {
    std::this_thread::sleep_for(std::chrono::microseconds(DAEMON_ACCEPT_CONN_SLEEP));
}


void cService::start() {
    if (is_running) {
        syslog(LOG_NOTICE, "Service %s is already running, not starting again...", service_id.c_str());
        return;
    }

    // Set-up daemon and communication socket; start a thread that periodically release stale connection threads and resources
    is_running = true;
    initDaemon();
    initSocket();
    run_cleanup_thread = true;
    std::thread cleanup_thread = std::thread(&cService::cleanConns, this);
    scheduler->start();

    // Keep accepting connections
    try {
        while (true) {
            if (!remote) {
                acceptConnectionLocal();
            } else {
                acceptConnectionRemote();
            }
        }
    } catch (const std::exception &e) {
        syslog(LOG_ERR, "Exception in main loop: %s", e.what());
    } catch (...) {
        syslog(LOG_ERR, "Unknown exception in main loop");
    }

    syslog(LOG_WARNING, "Daemon exiting unexpectedly");
}

}
