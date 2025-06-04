#pragma once

#include <mutex>
#include <condition_variable>
#include <deque>

template <typename T>
class blocking_queue {
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