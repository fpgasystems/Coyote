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

#ifndef _COYOTE_CFUNC_HPP_
#define _COYOTE_CFUNC_HPP_

#include <vector>
#include <string>
#include <cstdint>
#include <functional>
#include <filesystem>

#include <coyote/bFunc.hpp>
#include <coyote/cThread.hpp>

namespace coyote {

/**
 * @brief User-defined functions
 *
 * This class is a template for user-defined functions.
 * Each function is associated with a specific application bitstream
 * and the corresponding software-side function to be executed.
 * The functions are implemented using variadic templates to allow for
 * a variable number of parameters to be passed. This class is expected
 * to be used in conjuction with Coyote services (cService) and requests (cReq).
 * For an example, refer to Example 9 in examples/.
 *
 * @note Since this class is a template, it must be implemented in the header file
 * Otherwise, it leads to compilatiation errors. An alternative is to use
 * template specialization, but it is not applicable in this case, since the
 * function arguments are arbitrary and not known ahead of time.
 */
template<typename ret, typename... args>
class cFunc: public bFunc {

private: 

    /// Unique function identifier
    int32_t fid;

    /// Path to the application bitstream
    std::string app_bitstream;

    /// Once the bitstream is loaded from disk, this variable holds the pointer to the bitstream memory and its size
    std::pair<void*, uint32_t> bitstream_pointer;
    
    /**
     * @brief Body of the software function to be executed
     * 
     * Each function is a callable object, which by definition takes a 
     * cThread pointer which interacts with the vFPGA, and a variable 
     * number of arguments, that represent the parameters of the function.
     * ret represens the return type of the function.
     */
    std::function<ret(cThread*, args...)> fn;

public:

    /// Default constructor; converts the app_bitstream path to an absolute path
    cFunc(int32_t fid, std::string app_bitstream, std::function<ret(cThread*, args...)> fn) {
        this->fid = fid;
        this->app_bitstream = std::filesystem::absolute(app_bitstream).string();
        this->fn = fn;
    }

    /// Default destructor
    ~cFunc() {}

    /**
     * @brief Executes the function with the given arguments
     *
     * @param coyote_thread Pointer to the cThread object
     * @param x List of arguments passed as vector of char buffers, one buffer per argument
     * @return The result of the function execution, serialized into a char buffer
     *
     * @note The cService holds a list of functions registered with the background service
     * To do so, we need to implement a base (non-tempalated) bFunc class (otherwise
     * it becomes very hard to store the functions in a map). However, since the base
     * class is not templated, this function must also be non-templated. Therefore,
     * the run function takes the arguments as a vector of char buffers (std::vector<char>).
     * Each char buffer is then unpacked into the corresponding argument. There are alternatives
     * to this implementation (e.g., using std::any); however, using char buffer provides one of the
     * simplest solutions, with no reliance on complex data types. Additionally, when the function
     * arguments are received in the server (processRequests() function), they are naurally written to a 
     * char buffer, since they are contigious, byte-addressable and easily cast to other data types. 
     */
    std::vector<char> run(cThread* coyote_thread, const std::vector<std::vector<char>>& x) override {
        if (x.size() != sizeof...(args)) {
            throw std::invalid_argument("mismatch in argument count, exiting...");
        }

        // Unpack the arguments and call the function
        std::tuple<args...> function_arguments = unpackArgs(x, std::make_index_sequence<sizeof...(args)>{});
        ret tmp = std::apply(fn, std::tuple_cat(std::make_tuple(coyote_thread), function_arguments));

        // Copy the return value to a vector of char
        std::vector<char> ret_val(sizeof(ret));
        memcpy(ret_val.data(), &tmp, sizeof(ret));
        return ret_val;
    }

    /**
     * @brief Returns a pointer to the bitstream memory and its size
     */
    std::pair<void*, uint32_t> getBitstreamPointer() const override {
        return bitstream_pointer;
    }

    /**
     * @brief Sets the bitstream memory for this function
     *
     * Once the bistream has been loaded from disk to memory (using functions cRcnfg),
     * this function updates the bitstream_pointer variable with its address and size.
     * 
     * @param bitstream_pointer A pair containing the pointer to the bitstream memory and its size
     */
    void setBitstreamPointer(std::pair<void*, uint32_t> bitstream_pointer) override {
        this->bitstream_pointer = bitstream_pointer;
    }

    /** 
     * @brief Returns a vector of sizes, one for of the function arguments
     * 
     * Example: For args = {int64_t, float, bool}, the return is std::vector<size_t> = {8, 4, 1}
     *
     * @return A vector of sizes of the function argument
     */ 
    std::vector<size_t> getArgumentSizes() const override { return { sizeof(args)... }; }

    /// Similar to above, returns the size of the return value of the function
    size_t getReturnSize() const override { return sizeof(ret); }

    /// Getter: Function ID
    int32_t getFid() const override { return fid; }

    /// Getter: Bitstream path
    std::string getBitstreamPath() const override { return app_bitstream; }

private:
    /**
     * @brief Utility function; unpacks the arguments from a vector of char buffers into a tuple
     *
     * This function uses parameter pack expansion and lambda function to unpack the arguments
     * 
     * @param x Vector of char buffers, one for each argument
     * @param I Index sequence for unpacking
     * @return A tuple containing the unpacked arguments
     */
    template<std::size_t... I>
    std::tuple<args...> unpackArgs(const std::vector<std::vector<char>>& x, std::index_sequence<I...>) {
        /*
         * First, define a lambda function that converts one of the char buffers
         * into the corresponding argument type. The lambda function has access to all
         * variables in the current scope, due to the capture by reference [&]. Second,
         * use the parameter pack expansion to call the lambda function for each argument
         * in the tuple. In this case, the parameter pack expansion is done over the
         * args... and I... variables. In C++, expanding over multiple parameter packs
         * is possible, as long as they are of the same size. The parameters are always
         * expanded at the same index, i.e. arg[1] and I[1] are passed to the 2nd (zero-counding)
         * call of the lambda function. An index_sequence simply generates, at compile-time,
         * a sequence of non-negative integers, which cam be used to index parameters and lists.
         */
        
        return std::tuple<args...>([&]() {
            args value;
            memcpy(&value, x[I].data(), sizeof(args));
            return value;
        }()...);
    }

};

}

#endif // _COYOTE_CFUNC_HPP_
