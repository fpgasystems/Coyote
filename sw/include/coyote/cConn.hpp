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

#ifndef _COYOTE_CCONN_HPP_
#define _COYOTE_CCONN_HPP_

#include <atomic>
#include <string>
#include <vector>
#include <iostream>
#include <unistd.h>
#include <sys/un.h>
#include <sys/socket.h>

#include <coyote/cTask.hpp>
#include <coyote/cDefs.hpp>

namespace coyote {

/**
 * @brief Coyote connection class
 * 
 * A utility class that allows clients to connect to a Coyote background service
 * and submit tasks to be executed on the server side. The class supports both
 * blocking and non-blocking tasks.
 */
class cConn {

private: 

    /// Connection socket file descriptor
    int sockfd = -1;

    /// An atomic variable; used for generating unique IDs for tasks
    std::atomic<int32_t> task_counter;

    /// A map of submitted tasks
    std::map<int32_t, std::unique_ptr<cTask>> tasks;

    /// A dedicated thread that periodically checks for completed tasks
    std::thread completion_thread;

    /// Set to true when the completion thread is running; cleared by the thread if the connection to the server is lost
    std::atomic<bool> run_thread = { false };

    /// Error of the last failed call (or of the constructor), see getLastError()
    CoyoteError last_error = { CoyoteError::OK };

    /**
     * @brief Periodically checks for completed tasks and update the task map
     */
    void checkCompletedTasks();

    /// Returns isValid(); if false, prints one line naming call, so that a failed constructor cannot go unnoticed
    bool checkValid(const char* call) const;

    /// Records err as the last error and prints one line, "ERROR: cConn::<call>: <message> (<detail>)", see printError
    template<typename... Args>
    void setError(CoyoteError err, const char* detail, const Args&... call) {
        last_error = err;
        printError(err, detail, "cConn::", call...);
    }

public:

    /** 
     * @brief Default constructor for local connections
     *
     * When called, this constructor create a local connection to a Coyote service, as implemented in cService.hpp
     *
     * @param sock_name The name of the Coyote socket, as registed by the server
     *
     * @note Does not throw; on failure, it prints the error and the connection is invalid, see isValid() and getLastError()
     */
    cConn(std::string sock_name);

    /// Default destructor; sends a request to close the connection
    ~cConn();

    /// Returns true if the connection to the server was established; all calls on an invalid connection fail with CoyoteError::NO_DEVICE
    bool isValid() const;

    /// Returns the error of the last failed call or of the constructor (CoyoteError::OK if none failed)
    CoyoteError getLastError() const;

    /**
     * @brief Checks if a task with the given ID is completed
     *
     * @param tid Task ID to check
     * @return true if the task is completed, false otherwise
     */
    bool isTaskCompleted(int32_t tid);

    /**
     * @brief Submits a task to the Coyote service; blocking - waits until the task is completed
     *
     * @param fid Function ID of the request
     * @param result The return value of executed function
     * @param msg Variable number of arguments to be sent to the server
     * @return CoyoteError::OK on success; INVALID_ARG if the server rejected the task (e.g., unknown function ID or wrong arguments)
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note Users must ensure they pass the correct template arguments, matching the function signature
     * on the server; the server simply serializes a byte array into the target arguments; so if 
     * incorrect templates are passed, a wrong value may be returned. 
     */
    template<typename ret, typename... args>
    CoyoteError task(int32_t fid, ret& result, args... msg) {
        DBG1("cConn: Submitting a blocking task; fid" << fid); 
        if (!checkValid("task")) { return CoyoteError::NO_DEVICE; }
       
        /*
         * Add task to the map with a unique ID. In general, the cTask consturctor 
         * expects the function arguments and a cThread; here, however, they are not needed, 
         * since the function is executed on the server side. The purpose of the cTask
         * in this class is to poll on its completion and return the result.
        */
        int32_t tid = task_counter++;

        tasks.emplace(tid, std::make_unique<cTask>(tid, fid, sizeof(ret)));
                
        // Send opcode, function ID and task ID to server
        int32_t req[3];
        req[0] = DEF_OP_SUBMIT_TASK;
        req[1] = fid;
        req[2] = tid;
        bool sent = write(sockfd, &req, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t);

        // Send the payload using parameter pack expansion and a lambda function; stops at the first failed write
        auto f_wr = [&](auto& x){
            using arg_type = decltype(x);
            size_t arg_size = sizeof(arg_type);

            if (sent && write(sockfd, &x, arg_size) != arg_size) {
                sent = false;
            }
        };
        (f_wr(msg), ...);
        if (!sent) {
            int e = errno;
            setError(errnoToError(e), strerror(e), "task(fid=", fid, ")");
            return errnoToError(e);
        }

        // Wait until the task has been marked as completed, or the connection to the server is lost
        while (!tasks[tid]->isCompleted() && run_thread) {
            std::this_thread::sleep_for(std::chrono::microseconds(SLEEP_INTERVAL_CLIENT_CONN_MANAGER)); 
        }
        if (!tasks[tid]->isCompleted()) {
            setError(CoyoteError::NO_DEVICE, "connection to the server lost", "task(fid=", fid, ")");
            return CoyoteError::NO_DEVICE;
        }

        return getTaskReturnValue(tid, result);
    }

    /**
     * @brief Submits a task to the Coyote service; non-blocking - exits immediately after sending the request
     *
     * Users should use isTaskCompleted(int32_t tid) to query the status of the task
     * and if complete, getTaskReturnValue(tid, result) to retrieve the return value.
     *
     * @param fid Function ID of the request
     * @param tid Unique task ID
     * @param msg Variable number of arguments to be sent to the server
     * @return CoyoteError::OK on success
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note Users must ensure they pass the correct template arguments, matching the function signature
     * on the server; the server simply serializes a byte array into the target arguments; so if 
     * incorrect templates are passed, a wrong value may be returned. 
     */
    template<typename ret, typename... args>
    CoyoteError iTask(int32_t fid, int32_t& tid, args... msg) {
        DBG1("cConn: Submitting a non-blocking task; fid" << fid); 
        if (!checkValid("iTask")) { return CoyoteError::NO_DEVICE; }
       
        tid = task_counter++;
        tasks.emplace(tid, std::make_unique<cTask>(tid, fid, sizeof(ret)));
        // Send opcode, function ID and task ID to server
        int32_t req[3];
        req[0] = DEF_OP_SUBMIT_TASK;
        req[1] = fid;
        req[2] = tid;
        bool sent = write(sockfd, &req, 3 * sizeof(int32_t)) == 3 * sizeof(int32_t);

        // Send the payload using parameter pack expansion and a lambda function; stops at the first failed write
        auto f_wr = [&](auto& x){
            using arg_type = decltype(x);
            size_t arg_size = sizeof(arg_type);

            if (sent && write(sockfd, &x, arg_size) != arg_size) {
                sent = false;
            }
        };
        (f_wr(msg), ...);
        if (!sent) {
            int e = errno;
            setError(errnoToError(e), strerror(e), "iTask(fid=", fid, ")");
            return errnoToError(e);
        }

        return CoyoteError::OK;
    }


    /**
     * @brief Obtains the task return value from the server
     *
     * This function should only be called after the task has been submitted
     * and marked as completed, by checking isTaskCompleted(int32_t tid).
     *
     * @param tid Task ID, as obtained from iTask()
     * @param result The return value of executed function
     * @return CoyoteError::OK on success; BUSY if the task is not completed yet,
     * INVALID_ARG for an unknown task or if the server rejected the task (e.g., unknown function ID or wrong arguments)
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note Users must ensure they pass the correct template for ret, matching the function signature
     * on the server; the server simply serializes a byte array into the response; so if an incorrect
     * incorrect template is passed, a wrong value may be returned. 
     */
    template<typename ret>
    CoyoteError getTaskReturnValue(int32_t tid, ret& result) {
        if (!checkValid("getTaskReturnValue")) { return CoyoteError::NO_DEVICE; }
        if (tasks.find(tid) == tasks.end()) {
            setError(CoyoteError::INVALID_ARG, "task not found", "getTaskReturnValue(tid=", tid, ")");
            return CoyoteError::INVALID_ARG;
        }
        if (!tasks[tid]->isCompleted()) {
            setError(CoyoteError::BUSY, "task not completed yet", "getTaskReturnValue(tid=", tid, ")");
            return CoyoteError::BUSY;
        }
        
        int32_t ret_code = tasks[tid]->getRetCode();
        if (ret_code != 0) {
            setError(
                CoyoteError::INVALID_ARG, "the server rejected the task; check the function ID and the number and type of arguments",
                "getTaskReturnValue(tid=", tid, ")"
            );
            return CoyoteError::INVALID_ARG;
        }

        std::vector<char> tmp = tasks[tid]->getRetVal();
        memcpy(&result, tmp.data(), sizeof(ret));

        DBG1("cConn: Request completed; return code" << ret_code << " return value: " << result);
        return CoyoteError::OK;
    }

};

}

#endif // _COYOTE_CCONN_HPP_
