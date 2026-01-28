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

#ifndef _COYOTE_CTASK_HPP_
#define _COYOTE_CTASK_HPP_

#include <map>
#include <vector>
#include <cstdint>

#include <coyote/cThread.hpp>

namespace coyote {

/**
 * @brief A task represents a single request to execute a function
 *
 * This class encapsulates all the necessary logic and metadata to execute
 * a Coyote function (cFunc). For example, the Coyote scheduler (cSched) keeps
 * track of all the tasks and based on the scheduling policy, decides the next
 * one to be executed. 
 */
class cTask {

private: 
    /// Unique task identifier
    int32_t tid;

    /// ID of the function to be executed for this task o
    int32_t fid;

    /// Set to true when the task is completed
    bool is_completed;

    /// Pointer to the cThread that executes this task (it is passed to the cFunc as the first argument)
    cThread* cthread;

    /// Arguments for the function to be executed; see cFunc for detail on why a vector of char buffers is used
    std::vector<std::vector<char>> fn_args;

    /// Function return value; see cFunc for detail on why a char buffer is is used
    std::vector<char> ret_val;

    /// Size of the function return value; primarily a util value used for deserializing the char buffer
    size_t ret_val_size;

    /// Function return code; a non-zero value indicates an error in the function execution
    int32_t ret_code;

public:
    /// Default constructor; sets the unique task ID and the associated function, sets the args, init other params to default value
    cTask(int32_t tid, int32_t fid, size_t ret_val_size, cThread* cthread = nullptr, std::vector<std::vector<char>> fn_args = {});

    /// Getter: Task ID
    int32_t getTid() const;

    /// Getter: Function ID
    int32_t getFid() const;

    /// Checks if the task is completed
    bool isCompleted() const;

    /// Sets the value of is_completed
    void setCompleted(bool val);

    /// Getter: Pointer to associated cThread
    cThread* getCThread() const;

    /// Getter: Function arguments
    std::vector<std::vector<char>> getArgs() const;

    /// Getter: Function return value
    std::vector<char> getRetVal() const;

    /// Setter: Function return value
    void setRetVal(const std::vector<char> retval);

    /// Getter: Function return value size
    size_t getRetValSize() const;

    /// Getter: Function return code
    int32_t getRetCode() const;

    /// Setter: Function return code
    void setRetCode(int32_t retcode);
};

}

#endif // _COYOTE_CTASK_HPP_
