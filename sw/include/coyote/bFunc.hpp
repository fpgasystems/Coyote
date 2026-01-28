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

#ifndef _COYOTE_BFUNC_HPP_
#define _COYOTE_BFUNC_HPP_

#include <string>
#include <vector>

#include <coyote/cThread.hpp>

namespace coyote {

/**
 * @brief Base user function
 *
 * This class should not be used directly; instead it is be inherited in the cFunc class,
 * which defines the arbitrary user functions and the corresponding bitstreams.
 * Therefore this class is fully abstract and all the functions are pure virtual.
 * Additionally, since it is a fully abstract class, there is no corresponding .cpp file.
 *
 * The only reason this class exists is because the cFunc class has a variadic
 * template, making it difficult to include in other classes. For example,
 * the cService class keeps a map of functions added to the Coyote background service, and,
 * since each function is user-defined, it can have different templates and arguments. 
 */
class bFunc {

public:
    virtual ~bFunc() {}

    virtual std::vector<char> run(cThread* coyote_thread, const std::vector<std::vector<char>>& args) = 0;

    virtual int32_t getFid() const = 0;

    virtual std::string getBitstreamPath() const = 0;

    virtual std::pair<void*, uint32_t> getBitstreamPointer() const = 0;

    virtual void setBitstreamPointer(std::pair<void*, uint32_t> bitstream_pointer) = 0;
    
    virtual std::vector<size_t> getArgumentSizes() const = 0;
    
    virtual size_t getReturnSize() const = 0;
};

}

#endif // _COYOTE_BFUNC_HPP_
