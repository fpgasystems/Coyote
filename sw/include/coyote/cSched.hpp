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

#ifndef _COYOTE_CSCHED_HPP_
#define _COYOTE_CSCHED_HPP_

#include <map>
#include <mutex>
#include <vector>
#include <fstream>
#include <cstdint>
#include <syslog.h>

#include <coyote/bFunc.hpp>
#include <coyote/cTask.hpp>
#include <coyote/cRcnfg.hpp>

namespace coyote {

/**
 * @brief Coyote run-time scheduler
 *
 * The scheduler is responsible for managing tasks and functions in the Coyote
 * Users can submit aritrary functions, defined through the cFunc class, to the scheduler.
 * Each function contains a path to its app bistream and the corresponding software-side code.
 * Then, the tasks can be submitted to the scheduler (most commonly done from the cService, though
 * it is possible to write code that interacts directly with the scheduler), which dispatches the tasks 
 * based on a scheduling policy. Where needed, the scheduler will also reconfigure the vFPGA bitstream
 * with the one correct for the function. Currently, there are two scheduling policieies implemented:
 * (1) first-come, first-served (FCFS) and (2) minimize reconfigurations. The second one will always
 * execute all the tasks with the same bitstream, avoiding the latency inccured by partial reconfiguration,
 * before proceeding to the next task with a different bitstream.
 *
 * TODO:
 * - Implement more scheduling policies, such as priority-based scheduling
 */
class cSched: public cRcnfg {

private:

    /** 
     * @brief Instances of the schedulers
     *
     * We only allow one instance of the scheduler per vFPGA on a single device, 
     * to avoid conflicting scheduling decisions and reconfigurations.
     */
    static std::map<std::string, cSched*> schedulers;

    /// vFPGA ID associated with the scheduler
    int32_t vfid;

    /// Allow reordering of tasks to minimize number of reconfigurations
    bool reorder;

    /// Shell configuration as set before hardware synthesis in CMake
    fpgaCnfg fcnfg;

    /// A map of the functions loaded to the scheduler, each identified by a unique function ID
    std::map<int32_t, std::unique_ptr<bFunc>> functions;

    /// A list of tasks submitted to the scheduler
    std::vector<std::unique_ptr<cTask>> tasks;

    /// A simple map from task ID to its position in the tasks vector; simply used for faster lookups of individual tasks
    std::map<int32_t, int> task_id_map;

    /**
     * @brief Task lock; there are multiple concurrent threads that access the tasks 
     * vector, and since vectors can relocate data (e.g., when adding new elements),
     * this can lead to undefined behaviour. E.g., the scheduler thread iterates
     * through the tasks vector, while the addTask() function could be called in the meantime,
     * which would cause the vector to be resized and may cause the iterators to become invalid.
     */ 
    std::mutex tlock;

    /// A dedicated thread that runs the scheduler
    std::thread scheduler_thread;

    /// A flag indicating whether the scheduler thread is running
    bool scheduler_running;

    /// The currently loaded bitstream
    std::string current_bitstream;

    /// Default constructor; private to ensure the class is implemented as a singleton
    cSched(int32_t vfid, uint32_t device, bool reorder, std::string current_bitstream);

    /**
     * @brief A utility function that is reaused throughut the scheduler
     * Does the following checks:
     * 1. Checks if the task ID is present in the task_id_map
     * 2. Checks whether the task is non-NULL
     * 3. As a common sanity check, ensures the ID in the map and the ID in the vector match
     *  If not, something went seriously wrong when inserting the task to the list of tasks.
     *
     * @param tid Task ID to check
     * @return true if the task is found and valid, false otherwise
     */
    bool taskChecker(int32_t tid);

    /**
     * @brief The main function of the scheduler
     *
     * It iterates through the list of outstanding tasks and
     * executed the outstanding ones. The scheduling policy depends
     * on the variable scheduling_policy, passed to the class constructor.
     * This function will also reconfigure the vFPGA bitstream, if needed.
     */
    void schedule();

public:
    /**
     * @brief Creates an instance of the scheduler for a vFPGA
     *
     * If an instance already exists, return the existing instance ("singleton" implementation)
     *
     * @param vfid Virtual FPGA ID associated with the service
     * @param device Device number, for systems with multiple vFPGAs 
     * @param reorder If true, the scheduler will reorder tasks to minimize the number of reconfigurations.
     * @param current_bitstream If a user alread loaded an application bitstream, it can be marked as the active one
     * @return Pointer to a cSched instance
     *
     * @note When partial reconfiguration is enabled, the parameter current_bitstream is ignored, since the scheduler will
     * automatically reconfigure the vFPGA with the bitstream corresponding to the function of the task being executed. However,
     * when partial reconfiguration is not enabled, users must specify the current bitstream, so that all tasks that match the bitstream
     * can still be executed without reconfiguration. This scenario could be beneficial for priority-based scheduling or in conjuction with
     * the cService class with one type of function but mutliple connected clients to the service. See schedule(...) for more details.
     */
    static cSched* getInstance(int32_t vfid, uint32_t device = 0, bool reorder = true, std::string current_bitstream = "") {
        std::string tmp_id = std::to_string(device) + "-" + std::to_string(vfid);
    
        if (schedulers.find(tmp_id) != schedulers.end()) {
            if (schedulers[tmp_id] == nullptr) {
            schedulers[tmp_id] = new cSched(vfid, device, reorder, current_bitstream);
            }
        } else {
            schedulers[tmp_id] = new cSched(vfid, device, reorder, current_bitstream);
        }

        return schedulers[tmp_id];
    }

    /**
     * @brief Start the scheduler
     */
    void start();

    /**
     * @brief Stops the scheduler and cleans up resources
     */
    void stop();

    /**
     * @brief Adds a task to list of tasks to be executed by the scheduler
     *
     * @param task Unique pointer to the cTask object representing the task
     * @return true if the task was added successfully, false if the task ID already exists or if the task is associated with a function that is not registered
     */
    bool addTask(std::unique_ptr<cTask> task);

    /**
     * @brief Checks if a task with a given ID is completed
     *
     * @param tid Task ID to check
     * @return true if the task is completed, false otherwise
     *
     * @note If task is not found, false is returned
     */
    bool isTaskCompleted(int32_t tid);

    /**
     * @brief Gets the task with the given ID
     *
     * @param tid Task ID to get
     * @return Pointer to the cTask object if found, nullptr otherwise
     */
    cTask* getTask(int32_t tid);

    /**
     * @brief Checks if a function with the given ID is registered in the scheduler
     *
     * @param fid Function ID to check
     */
    bool isFunctionRegistered(int32_t fid);

    /**
     * @brief Gets the function with the given ID
     *
     * @param fid Function ID to get
     * @return Pointer to the cFunc object if found, nullptr otherwise
     */
    bFunc* getFunction(int32_t fid);

    /**
     * @brief Adds an arbitrary user function to the scheduler
     *
     * Each function is uniquely identified by its ID and holds
     * information about the function: path to its bistream
     * and the corresponding software-side code.
     *
     * @param fn Unique pointer to the bFunc object representing the function
     * @return 0 if the function was added successfully, 1 if bitstream cannot be opened, 2 if the function ID already exists 
     *
     * @note Implemented in the header file, since the function is a template.
     */
    int addFunction(std::unique_ptr<bFunc> fn) {
        int32_t fid = fn->getFid();
        if (functions.find(fid) == functions.end()) {
            functions.emplace(fid, std::move(fn));

            std::ifstream bitstream_file(functions[fid]->getBitstreamPath(), std::ios::ate | std::ios::binary);
            if (!bitstream_file) {
		        syslog(LOG_ERR, "Function %d bitstream could not be opened; please check the provided bitstream path", fid);
                functions.erase(fid);
                return 1;
	        }

            try {
                functions[fid]->setBitstreamPointer(readBitstream(bitstream_file));
            } catch (const std::exception &e) {
                syslog(LOG_ERR, "Exception while loading function fid %d bitstream: %s", fid, e.what());
                functions.erase(fid);
                return 1;
            }

            bitstream_file.close();
            syslog(LOG_NOTICE, "Added function with fid %d", fid);
            return 0;
        
        } else {
            syslog(LOG_WARNING, "Function with fid %d already exists, skipping...", fid);
            return 2;
        }
    }

};

}

#endif // _COYOTE_CSCHED_HPP_
