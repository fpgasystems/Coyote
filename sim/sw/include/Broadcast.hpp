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

#ifndef _COYOTE_BROADCAST_HPP_
#define _COYOTE_BROADCAST_HPP_

#include <mutex>
#include <condition_variable>

/**
 * Broadcast that has ordering. The way to use this is:
 * 1. Register yourself as a receiver which returns the last generation
 * 2. Call receive_any in a loop while incrementing the generation counter until you get the desired 
 *    output.
 * 3. Unregister yourself as a receiver
 * 
 * The broadcast only continues when it gets acknowledgements from all receivers.
 */
template <typename T>
class Broadcast {
public:
    Broadcast() : num_receivers(0), is_broadcast_active(false), curr_generation(0), ack_count(0) {}

    /**
     * Register a new receiver for broadcasts.
     * 
     * @return The current generation that has to be passed ot receive(...)
     */
    size_t register_receiver() {
        std::lock_guard<std::mutex> lock(mtx);
        num_receivers++;
        return curr_generation;
    }

    /**
     * Unregister a receiver. Wakes up the broadcast if there is an active broadcast and all other 
     * receivers have acknowledged already.
     */
    void unregister_receiver() {
        std::lock_guard<std::mutex> lock(mtx);
        if (num_receivers > 0) {
            num_receivers--;

            if (is_broadcast_active && ack_count >= num_receivers) {
                ack_cv.notify_one();
            }
        }
    }

    /**
     * Broadcast data to all receivers. Blocks until all receivers have acknowledged receipt.
     * 
     * @param data The data to broadcast
     */
    void broadcast(const T &data) {
        std::unique_lock<std::mutex> lock(mtx);
        
        if (num_receivers == 0) {
            return;
        }

        // Wait for any previous broadcast to complete
        ack_cv.wait(lock, [this] { 
            return !is_broadcast_active; 
        });

        // Set up new broadcast
        this->data = data;
        curr_generation++;
        ack_count = 0;
        is_broadcast_active = true;

        // Wake up all waiting receivers
        broadcast_cv.notify_all();

        // Wait for all acknowledgments
        ack_cv.wait(lock, [this] {
            return ack_count >= num_receivers;
        });

        // Mark broadcast as complete
        is_broadcast_active = false;
        
        // Notify any waiting broadcaster (if broadcast is called again)
        ack_cv.notify_one();
    }

    /**
     * Receive data from broadcast. Blocks until new data is available. Automatically acknowledges 
     * receipt.
     * 
     * @param last_generation The generation last seen by this receiver (0 initially)
     * @return Data from broadcast
     */
    T receive_any(size_t last_generation) {
        std::unique_lock<std::mutex> lock(mtx);

        // Wait for a new broadcast (generation must be greater than last seen)
        broadcast_cv.wait(lock, [this, last_generation] {
            return is_broadcast_active && curr_generation > last_generation;
        });

        // Copy data before acknowledging
        T received_data(data);

        // Acknowledge receipt
        ack_count++;
        
        // If we're the last receiver, notify broadcaster
        if (ack_count >= num_receivers) {
            ack_cv.notify_one();
        }

        return std::move(received_data);
    }

private:
    std::mutex              mtx;
    std::condition_variable broadcast_cv;
    std::condition_variable ack_cv;
    
    T      data;
    size_t num_receivers;
    bool   is_broadcast_active;
    size_t curr_generation;
    size_t ack_count;
};

#endif
