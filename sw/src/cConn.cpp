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

#include <coyote/cConn.hpp>

namespace coyote {      
    
cConn::cConn(std::string sock_name) {  
    DBG3("cConn: Called the constructor for a local connection (AF_UNIX), sock_name" << sock_name); 

    // On failure, print the error and leave the connection invalid (sockfd = -1); a missing or refusing socket means no service is running
    auto fail = [&](const char* step) {
        int e = errno;
        setError(e == ENOENT || e == ECONNREFUSED ? CoyoteError::NO_DEVICE : errnoToError(e), sysDetail(step, e).c_str(), "cConn(sock_name=", sock_name, ")");
        if (sockfd != -1) {
            close(sockfd);
            sockfd = -1;
        }
    };

    // The path must fit into sockaddr_un::sun_path, including the terminating zero
    struct sockaddr_un server = {};
    if (sock_name.size() >= sizeof(server.sun_path)) {
        setError(CoyoteError::INVALID_ARG, "socket path too long", "cConn(sock_name=", sock_name, ")");
        return;
    }

    // Open a socket and try to connect it to the server
    if ((sockfd = socket(AF_UNIX, SOCK_STREAM, 0)) == -1) {
        fail("socket");
        return;
    }

    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, sock_name.c_str());

    if (connect(sockfd, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
        fail("connect");
        return;
    }

    /*
    // Since there is a dedicated thread that listens for task completions,
    // set a timout for the socket, to avoid blocking other call while waiting for the server to respond
    if (setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &CLIENT_RECV_TIMEOUT, sizeof(CLIENT_RECV_TIMEOUT)) < 0) {
        throw std::runtime_error("ERROR: Failed to set socket timeout");
    }
    */
    
    // Register the PID with the server
    pid_t pid = getpid();
    if (send(sockfd, &pid, sizeof(pid_t), MSG_NOSIGNAL) != sizeof(pid_t)) {
        fail("send pid");
        return;
    }

    /// Initialize the completion listener thread & the rest of the variables
    run_thread = true;
    task_counter = 0;
    try {
        completion_thread = std::thread(&cConn::checkCompletedTasks, this);
    } catch (const std::system_error& e) {
        run_thread = false;
        errno = e.code().value();
        fail("completion thread");
        return;
    }
    std::cout << "Client connected" << std::endl;
}

cConn::~cConn() {
    DBG3("cConn: Called the destructor, closing the connection");
    if (!isValid()) { return; }

    /*
     * When function request are submitted, the client sends three values: opcode (DEF_OP_SUBMIT_TASK), function ID and task ID.
     * However, to close the connection, only one value needs to be sent (the opcode). The alternative is to first send the
     * opcode (DEF_OP_CLOSE_CONN or DEF_OP_SUBMIT_TASK) and in the case of the request, then send the function and task ID. 
     * However, this adds unnecessary latency due to IPC as well as complexity to the code. Therefore, send three values here
     * even though only the first one is used to close the connection; the rest are ignored.
     */
    int32_t req[3];
    req[0] = DEF_OP_CLOSE_CONN;
    run_thread = false;
    if (send(sockfd, &req, 3 * sizeof(int32_t), MSG_NOSIGNAL) != 3 * sizeof(int32_t)) {
        std::cerr << "ERROR: Failed to send close connection request to the server" << std::endl;
    }

    // Terminate completion thread; shutdown() wakes it up if it is blocked in read()
    shutdown(sockfd, SHUT_RDWR);
    if (completion_thread.joinable()) {
        completion_thread.join();
    }
    close(sockfd);
    std::cout << "Successfully closed connection to the server" << std::endl;
}

bool cConn::isValid() const { return sockfd != -1; }

bool cConn::checkValid(const char* call) const {
    if (!isValid()) {
        printError(CoyoteError::NO_DEVICE, "the cConn is not valid, its constructor failed", "cConn::", call);
    }
    return isValid();
}

CoyoteError cConn::getLastError() const { return last_error; }

void cConn::checkCompletedTasks() {
    DBG3("cConn: Starting the completion listener thread");
    
    while (run_thread) {
        // Check if the server wrote the task ID and the completion code; if yes, process task completion
        char recv_buff[RECV_BUFF_SIZE];
        ssize_t n = read(sockfd, recv_buff, 2 * sizeof(int32_t));
        if (n == 0 || (n == -1 && errno != EINTR)) {
            // The server closed the connection (or the socket failed); waiting tasks give up, see task()
            if (run_thread) {
                printError(CoyoteError::NO_DEVICE, n == 0 ? "connection closed by the server" : strerror(errno), "cConn::checkCompletedTasks()");
            }
            run_thread = false;
            break;
        }

        if (n == 2 * sizeof(int32_t)) {

            int32_t task_id, ret_code;
            memcpy(&ret_code, recv_buff, sizeof(int32_t));
            memcpy(&task_id, recv_buff + sizeof(int32_t), sizeof(int32_t));
            if (tasks.find(task_id) != tasks.end()) {
                // Task exists & ret_code is zero; receive the return value from the server
                if (ret_code == 0) {
                    size_t ret_val_size = tasks[task_id]->getRetValSize();
                    if (read(sockfd, recv_buff, ret_val_size) != ret_val_size) {
                        // The stream is out of sync now; fail the task and stop
                        printError(CoyoteError::UNKNOWN, "failed to read the return value", "cConn::checkCompletedTasks(tid=", task_id, ")");
                        tasks[task_id]->setRetCode(1);
                        tasks[task_id]->setCompleted(true);
                        run_thread = false;
                        break;
                    }
                    std::vector<char> ret_val(recv_buff, recv_buff + ret_val_size);
                    tasks[task_id]->setRetVal(ret_val);
                    tasks[task_id]->setRetCode(ret_code);
                    tasks[task_id]->setCompleted(true);

                // Task exists, but server sent non-zero return code; mark as completed but don't store return value
                } else {
                    tasks[task_id]->setRetCode(ret_code);
                    tasks[task_id]->setCompleted(true);
                }
            }   
            
        }
        
        std::this_thread::sleep_for(std::chrono::microseconds(SLEEP_INTERVAL_CLIENT_CONN_MANAGER)); 
    }

    DBG3("cConn: Completion thread stopped");
}

bool cConn::isTaskCompleted(int32_t tid) {
    if (!checkValid("isTaskCompleted")) { return false; }
    if (tasks.find(tid) != tasks.end()) {
        // A lost connection ends the task as well, so a polling loop terminates; getTaskReturnValue() then returns NO_DEVICE
        return tasks[tid]->isCompleted() || !run_thread;
    } else {
        std::cerr << "ERROR: Task with ID " << tid << " not found when checking for completion" << std::endl;
        return false;
    }
}

}
