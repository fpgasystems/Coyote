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

#include <coyote/cSched.hpp>

namespace coyote {

std::map<std::string, cSched*> coyote::cSched::schedulers;

cSched::cSched(int32_t vfid, uint32_t device, bool reorder, std::string current_bitstream) : 
  vfid(vfid), cRcnfg(device), reorder(reorder), current_bitstream(current_bitstream), scheduler_running(false) {

    // Check if partial reconfiguration is enabled
    uint64_t tmp[2];
    if (ioctl(reconfig_dev_fd, IOCTL_PR_CNFG, &tmp)) {
        throw std::runtime_error("IOCTL_PR_CNFG failed, vfid: " + std::to_string(vfid));
    }
    fcnfg.en_pr = tmp[0];

    if (!fcnfg.en_pr) {
        syslog(LOG_WARNING, "Partial reconfiguration is not enabled; scheduler will only execute functions that match the current bitstream");
    } 

}

bool cSched::taskChecker(int32_t tid) {
    if (task_id_map.find(tid) == task_id_map.end()) {
        // Don't add print here; as this condition can happen often causing too many prints
        return false;
    }
    if (tasks[task_id_map[tid]] == nullptr) {
        syslog(LOG_WARNING, "Task with ID %d is null", tid);
        return false;
    }
    if (tasks[task_id_map[tid]]->getTid() != tid) {
        syslog(LOG_ERR, "UNEXPECTED BUG: ID from task map and list entry differ, map entry tid: %d", tid);
        return false;
    }
    return true;
}

void cSched::schedule() {
    syslog(LOG_NOTICE, "Starting scheduler thread for vfid %d", vfid);
    while (scheduler_running) {
        tlock.lock();
        int next_idx = -1;

        for (int i = 0; i < tasks.size(); i++) {
            // Check task is non-null and non-completed
            if (tasks[i] == nullptr) {
                continue;
            }

            if (tasks[i]->isCompleted()) {
                continue;
            }

            // Sanity check
            cThread* cthread = tasks[i]->getCThread();
            if (cthread == nullptr || functions.find(tasks[i]->getFid()) == functions.end()) {
                syslog(LOG_ERR, "UNEXPECTED BUG: Task with ID %d is missing its function signature or corresponding cThread, skipping", tasks[i]->getTid());
                tasks[i]->setRetCode(1);
                tasks[i]->setCompleted(true);
                continue;   
            }

            if (!reorder) {
                // If reordering is not enabled, process the first task found
                next_idx = i;
                break;
            } else {
                // Roerdering enabled => minimize the number of reconfigurations needed
                // However, if all tasks require reconfiguration, process the first one
                if (next_idx == -1) {
                    next_idx = i;
                }
                
                std::string target_bitstream = functions[tasks[i]->getFid()]->getBitstreamPath();
                if (current_bitstream != target_bitstream) {
                    // Skip this task, requires a different bitstream
                    continue; 
                } else {
                    // Process this task, its bitstream matches the current one
                    next_idx = i; 
                    break;
                }
            }
        }
        
        // Process next task, if there is one
        if (next_idx != -1) {
            // If the bitstream is not loaded, reconfigure the vFPGA
            std::string target_bitstream = functions[tasks[next_idx]->getFid()]->getBitstreamPath();
            if (current_bitstream != target_bitstream) {
                if (fcnfg.en_pr) {
                    try {
                        syslog(LOG_NOTICE, "Reconfiguring vFPGA %d, with bitstream %s for task with ID %d", vfid, target_bitstream.c_str(), tasks[next_idx]->getTid());
                        reconfigureBase(functions[tasks[next_idx]->getFid()]->getBitstreamPointer(), vfid);
                        current_bitstream = target_bitstream;
                        syslog(LOG_NOTICE, "Reconfiguration complete");
                    } catch (const std::exception &e) {
                        syslog(LOG_ERR, "Exception during reconfiguration: %s", e.what());
                        tasks[next_idx]->setRetCode(1);
                        tasks[next_idx]->setCompleted(true);
                    }
                } else {
                    syslog(LOG_WARNING, "Partial reconfiguration is not enabled, however, task with ID %d requires a different bitstream, skipping", tasks[next_idx]->getTid());
                    tasks[next_idx]->setRetCode(1);
                    tasks[next_idx]->setCompleted(true);
                }
            }
            
            // Execute the task
            if (!tasks[next_idx]->isCompleted()) {
                syslog(LOG_NOTICE, "Executing tid %d, fid %d, vfid %d", tasks[next_idx]->getTid(), functions[tasks[next_idx]->getFid()]->getFid(), vfid);
                cThread* cthread = tasks[next_idx]->getCThread();
                try {
                    cthread->lock();
                    std::vector<char> ret_val = functions[tasks[next_idx]->getFid()]->run(cthread, tasks[next_idx]->getArgs());
                    cthread->unlock();
                    tasks[next_idx]->setRetVal(ret_val);
                    tasks[next_idx]->setRetCode(0);
                    tasks[next_idx]->setCompleted(true);
                    syslog(LOG_NOTICE, "Executed task with ID %d", tasks[next_idx]->getTid());
                } catch (const std::exception &e) {
                    cthread->unlock();      // Unlock in case function execution failed
                    tasks[next_idx]->setRetCode(1);
                    tasks[next_idx]->setCompleted(true);
                    syslog(LOG_ERR, "Unknown error executing task with ID %d: %s", tasks[next_idx]->getTid(), e.what());
                }
            }
        }

        tlock.unlock();
        std::this_thread::sleep_for(std::chrono::nanoseconds(DAEMON_PROCESS_REQUESTS_SLEEP));
    }

    syslog(LOG_NOTICE, "Stopping scheduler thread for vfid %d", vfid);
}

void cSched::start() {
    if (scheduler_running) {
        syslog(LOG_NOTICE, "Scheduler thread for vfid %d is already running, not starting again", vfid);
        return;
    }
    scheduler_running = true;
    scheduler_thread = std::thread(&cSched::schedule, this);
}

void cSched::stop() {
    if (!scheduler_running) {
        syslog(LOG_NOTICE, "Scheduler thread for vfid %d is not running, nothing to stop", vfid);
        return;
    }
    scheduler_running = false;
    if (scheduler_thread.joinable()) {
        scheduler_thread.join();
    }
}

bool cSched::addTask(std::unique_ptr<cTask> task) {
    if (task == nullptr) {
        syslog(LOG_WARNING, "Task is null, cannot add to scheduler");
        return false;
    }

    int32_t tid = task->getTid();
    if (task_id_map.find(tid) != task_id_map.end()) {
        syslog(LOG_WARNING, "Task with ID %d already exists in the scheduler", task->getTid());
        return false;
    }

    if (!isFunctionRegistered(task->getFid())) {
        syslog(LOG_WARNING, "Function for task %d with fid %d is not registered in the scheduler", task->getTid(), task->getFid());
        return false;
    }

    tlock.lock();
    // IMPORTANT: Due to the move, after the following line, this function has no ownership of the task pointer
    // Therefore, any operation, such as task->(...), will cause a segmentation fault
    // Note the use of tid instead of task->getTid() to avoid dereferencing the moved task pointer
    tasks.push_back(std::move(task)); 
    task_id_map.emplace(tid, tasks.size() - 1);
    tlock.unlock();
    syslog(LOG_NOTICE, "Added task with ID %d to the scheduler", tid);
    return true;
}

bool cSched::isTaskCompleted(int32_t tid) {
    tlock.lock();
    if (!taskChecker(tid)) {
        tlock.unlock();
        return false;
    }
    bool completed = tasks[task_id_map[tid]]->isCompleted();
    tlock.unlock();
    return completed;
}

cTask* cSched::getTask(int32_t tid) {
    tlock.lock();
    if (!taskChecker(tid)) {
        tlock.unlock();
        return nullptr;
    }
    cTask* task = tasks[task_id_map[tid]].get();
    tlock.unlock();
    return task;
}

bool cSched::isFunctionRegistered(int32_t fid) {
    return functions.find(fid) != functions.end();
}

bFunc* cSched::getFunction(int32_t fid) {
    if (functions.find(fid) == functions.end()) {
        syslog(LOG_WARNING, "Function with ID %d not found in the scheduler, returning nullptr", fid);
        return nullptr;
    }
    return functions[fid].get();
}

}
