#ifndef BLOCKING_QUEUE_HPP
#define BLOCKING_QUEUE_HPP

#include <mutex>
#include <condition_variable>
#include <deque>

/**
 * Thread-safe queue that blocks whenever you try to pop an element while it is empty until there is an element in the queue again.
 * Used to communicate return values and simulation outputs between the different threads.
 */
template <typename T>
class BlockingQueue {
private:
    std::mutex              mtx;
    std::condition_variable cdv;
    std::deque<T>           que;

public:
    void push(T const& value) {
        {
            std::unique_lock<std::mutex> lock(this->mtx);
            que.push_front(value);
        }
        this->cdv.notify_one();
    }

    T pop() {
        std::unique_lock<std::mutex> lock(this->mtx);
        this->cdv.wait(lock, [=]{ return !this->que.empty(); });
        T rc(std::move(this->que.back()));
        this->que.pop_back();
        return rc;
    }
};

#endif
