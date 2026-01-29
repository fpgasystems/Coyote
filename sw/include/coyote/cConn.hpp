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

    /// Set to true when the completion thread is running
    bool run_thread;

    /**
     * @brief Periodically checks for completed tasks and update the task map
     */
    void checkCompletedTasks();

public:

    /** 
     * @brief Default constructor for local connections
     *
     * When called, this constructor create a local connection to a Coyote service, as implemented in cService.hpp
     *
     * @param sock_name The name of the Coyote socket, as registed by the server
     */
    cConn(std::string sock_name);

    /// Default destructor; sends a request to close the connection
    ~cConn();

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
     * @param msg Variable number of arguments to be sent to the server
     * @return The return value of executed function
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note This function can throw a runtime_error if there are failures
     * in the sending the payload to the server or if the server returns a non-zero code (e.g., timeouts, function not found, etc.)
     * @note Users must ensure they pass the correct template arguments, matching the function signature
     * on the server; the server simply serializes a byte array into the target arguments; so if 
     * incorrect templates are passed, a wrong value may be returned. 
     */
    template<typename ret, typename... args>
    ret task(int32_t fid, args... msg) {        
        DBG1("cConn: Submitting a blocking task; fid" << fid); 
       
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
        if (write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            throw std::runtime_error("ERROR: Failed to send request to server");
        }

        // Send the payload using parameter pack expansion and a lambda function 
        auto f_wr = [&](auto& x){
            using arg_type = decltype(x);
            size_t arg_size = sizeof(arg_type);

            if (write(sockfd, &x, arg_size) != arg_size) {
                throw std::runtime_error("ERROR: Failed to send function arguments to server");
            }
        };
        (f_wr(msg), ...);

        // Wait until the task has been marked as completed
        while (!tasks[tid]->isCompleted()) {
            std::this_thread::sleep_for(std::chrono::microseconds(SLEEP_INTERVAL_CLIENT_CONN_MANAGER)); 
        }

        // Check return code & if zero, parse return value
        int32_t ret_code = tasks[tid]->getRetCode();
        if (ret_code != 0) {
            throw std::runtime_error(
                std::string("ERROR: Server returned non-zero code for task with tid: ") + std::to_string(tid) +
                std::string("; please ensure the function ID is correct and registered with the server, ") +
                std::string("as well as that the correct number and type of arguments is being transmitted.").c_str()
            );
        }

        ret ret_val;
        std::vector<char> tmp = tasks[tid]->getRetVal();
        memcpy(&ret_val, tmp.data(), sizeof(ret));

        DBG1("cConn: Request completed; return code" << ret_code << " return value: " << ret_val); 
        return ret_val;
    }

    /**
     * @brief Submits a task to the Coyote service; non-blocking - exits immediately after sending the request
     *
     * Users should use isTaskCompleted(int32_t tid) to query the status of the task
     * and if complete, getTaskRetVal(int32_t tid) to retrieve the return value.   
     *
     * @param fid Function ID of the request
     * @param msg Variable number of arguments to be sent to the server
     * @return Unique task ID
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note This function can throw a runtime_error if there are failures
     * in the sending the payload to the server.
     * @note Users must ensure they pass the correct template arguments, matching the function signature
     * on the server; the server simply serializes a byte array into the target arguments; so if 
     * incorrect templates are passed, a wrong value may be returned. 
     */
    template<typename ret, typename... args>
    int32_t iTask(int32_t fid, args... msg) {        
        DBG1("cConn: Submitting a non-blocking task; fid" << fid); 
       
        int32_t tid = task_counter++;
        tasks.emplace(tid, std::make_unique<cTask>(tid, fid, sizeof(ret)));
        int32_t req[3];
        req[0] = DEF_OP_SUBMIT_TASK;
        req[1] = fid;
        req[2] = tid;
        if (write(sockfd, &req, 3 * sizeof(int32_t)) != 3 * sizeof(int32_t)) {
            throw std::runtime_error("ERROR: Failed to send request to server");
        }

        auto f_wr = [&](auto& x){
            using arg_type = decltype(x);
            size_t arg_size = sizeof(arg_type);

            if (write(sockfd, &x, arg_size) != arg_size) {
                throw std::runtime_error("ERROR: Failed to send function arguments to server");
            }
        };
        (f_wr(msg), ...);

        return tid;
    }


    /**
     * @brief Obtains the task return value from the server
     *
     * This function should only be called after the task has been submitted
     * and marked as completed, by checking isTaskCompleted(int32_t tid).
     * Otherwise, the return value may be wrong / zero.
     *
     * @param tid Task ID, as obtained from iTask()
     * @return The return value of executed function
     *
     * @note Implemnted in the header file, since it is a template function.
     * @note This function can throw a runtime_error if the server returns a non-zero code for the task.
     * This can happen if the requested function doesn't exist, timeouts, wrong argument serialization etc.
     * @note Users must ensure they pass the correct template for ret, matching the function signature
     * on the server; the server simply serializes a byte array into the response; so if an incorrect
     * incorrect template is passed, a wrong value may be returned. 
     */
    template<typename ret>
    ret getTaskReturnValue(int32_t tid) {
        if (tasks.find(tid) == tasks.end()) {
            throw std::runtime_error(
                std::string("ERROR: Task with id: ") + std::to_string(tid) +
                std::string("not found when getting return value").c_str()
            );
        }
        
        int32_t ret_code = tasks[tid]->getRetCode();
        if (ret_code != 0) {
            throw std::runtime_error(
                std::string("ERROR: Server returned non-zero code for task with tid: ") + std::to_string(tid) +
                std::string("; please ensure the function ID is correct and registered with the server, ") +
                std::string("as well as that the correct number and type of arguments is being transmitted.").c_str()
            );
        }

        ret ret_val;
        std::vector<char> tmp = tasks[tid]->getRetVal();
        memcpy(&ret_val, tmp.data(), sizeof(ret));

        DBG1("cConn: Request completed; return code" << ret_code << " return value: " << ret_val); 
        return ret_val;

    }

};

}

#endif // _COYOTE_CCONN_HPP_
