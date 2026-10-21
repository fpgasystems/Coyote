/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
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

/**
 * Thread-safe concurrent queue implementation using C++17 synchronization primitives.
 * Part of the Coyote CVRP GA asynchronous multi-vFPGA pipeline.
 */

#ifndef SAFE_QUEUE_HPP
#define SAFE_QUEUE_HPP

#include <condition_variable>
#include <mutex>
#include <optional>
#include <queue>
#include <utility>

template <typename T, typename Compare = std::greater<T>>
class SafeQueue {
public:
    SafeQueue() = default;
    ~SafeQueue() {
        shutdown();
    }

    SafeQueue(const SafeQueue&) = delete;
    SafeQueue& operator=(const SafeQueue&) = delete;

    void push(T value) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            queue_.push(std::move(value));
        }
        cv_.notify_all();
    }

    std::optional<T> pop() {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this]() { return !queue_.empty() || shutdown_; });
        if (queue_.empty()) {
            return std::nullopt;
        }
        T item = std::move(const_cast<T&>(queue_.top()));
        queue_.pop();
        return item;
    }

    bool try_pop(T &value) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (queue_.empty()) {
            return false;
        }
        value = std::move(const_cast<T&>(queue_.top()));
        queue_.pop();
        return true;
    }

    template <typename Predicate>
    std::optional<T> pop_if(Predicate pred) {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this, &pred]() {
            return shutdown_ || (!queue_.empty() && pred(queue_.top()));
        });
        if (queue_.empty() || !pred(queue_.top())) {
            return std::nullopt;
        }
        T item = std::move(const_cast<T&>(queue_.top()));
        queue_.pop();
        return item;
    }

    template <typename IdType>
    std::optional<T> pop_expected(IdType expected_id) {
        return pop_if([expected_id](const T &item) {
            return item.batch_id == expected_id;
        });
    }

    std::optional<T> top() const {
        std::lock_guard<std::mutex> lock(mutex_);
        if (queue_.empty()) {
            return std::nullopt;
        }
        return queue_.top();
    }

    void shutdown() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            shutdown_ = true;
        }
        cv_.notify_all();
    }

    bool is_shutdown() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return shutdown_;
    }

    std::size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.size();
    }

    bool empty() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return queue_.empty();
    }

private:
    std::priority_queue<T, std::vector<T>, Compare> queue_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    bool shutdown_ = false;
};

#endif // SAFE_QUEUE_HPP
