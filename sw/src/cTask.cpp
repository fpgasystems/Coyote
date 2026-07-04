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
 
#include <coyote/cTask.hpp>

namespace coyote {

cTask::cTask(int32_t tid, int32_t fid, size_t ret_val_size, cThread* cthread, std::vector<std::vector<char>> fn_args) 
    : tid(tid), fid(fid), is_completed(false), ret_val_size(ret_val_size), cthread(cthread), fn_args(std::move(fn_args)), ret_code(-1) {}

int32_t cTask::getTid() const {
    return tid;
}

int32_t cTask::getFid() const {
    return fid;
}

bool cTask::isCompleted() const {
    return is_completed;
}

void cTask::setCompleted(bool val) {
    is_completed = val;
}

cThread* cTask::getCThread() const {
    return cthread;
}

std::vector<std::vector<char>> cTask::getArgs() const {
    return fn_args;
}

std::vector<char> cTask::getRetVal() const {
    return ret_val;
}

void cTask::setRetVal(const std::vector<char> retval) {
    ret_val = retval;
}

size_t cTask::getRetValSize() const {
    return ret_val_size;
}

int32_t cTask::getRetCode() const {
    return ret_code;
}

void cTask::setRetCode(int32_t retcode) {
    ret_code = retcode;
}

}
