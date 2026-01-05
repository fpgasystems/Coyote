/**
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

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_BLOCKING_QUEUE_HPP_
#define _COYOTE_BLOCKING_QUEUE_HPP_

#include <mutex>
#include <condition_variable>
#include <deque>

/**
 * Thread-safe queue that blocks whenever you try to pop an element while it is empty until there is 
 * an element in the queue again. Used to communicate values between different threads.
 */
template <typename T>
class BlockingQueue {
public:
    void push(T const &value) noexcept {
        {
            std::lock_guard<std::mutex> lock(mtx);
            deque.push_front(value);
        }
        cv.notify_one();
    }

    bool pop(T &out) {
        std::unique_lock<std::mutex> lock(mtx);

        cv.wait(lock, [this]{ return !deque.empty() || stopped; });

        if (stopped && deque.empty()) {
            return false;
        }

        out = std::move(deque.back());
        deque.pop_back();
        return true;
    }

    void stop() noexcept {
        {
            std::lock_guard<std::mutex> lock(mtx);
            stopped = true;
        }
        cv.notify_all();
    }

private:
    std::mutex              mtx;
    std::condition_variable cv;
    std::deque<T>           deque;

    bool stopped{false};
};

#endif
