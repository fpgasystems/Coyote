/// @author    Johannes de Fine Licht (definelicht@inf.ethz.ch)
/// @copyright This software is copyrighted under the BSD 3-Clause License.

#pragma once

#ifndef HLSLIB_SYNTHESIS
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>
// #include "hlslib/Stream.h"
#endif

// This header provides functionality to simulate dataflow functions that
// include loops in conjunction with Stream.h.
//
// Dataflow functions must be wrapped in the HLSLIB_DATAFLOW_FUNCTION macro,
// which will launch them as a C++ thread when running simulation, but will
// fall back on normal function calls when running synthesis.
//
// The macro HLSLIB_DATAFLOW_INIT must be called before adding dataflow
// functions, in order to initialize the local context.
// The macro HLSLIB_DATAFLOW_FINALIZE must be called before returning from the
// top level function to join the dataflow threads.
//
// TODO: HLSLIB_DATAFLOW_FUNCTION does not work when calling templated functions
//       with multiple arguments, as it considers the comma a separator between
//       function arguments. Look into alternative implementation, or always use
//       variadic templates if newer Vivado HLS start supporting inlining the
//       called function (it currently fails with "no function body" on the
//       dataflow function in question).

namespace hlslib {

#ifdef HLSLIB_SYNTHESIS
#define HLSLIB_DATAFLOW_INIT()
#define HLSLIB_DATAFLOW_FUNCTION(func, ...) func(__VA_ARGS__)
#define HLSLIB_DATAFLOW_FINALIZE()
#else
namespace {
class _Dataflow {
 public:
  inline _Dataflow() {}
  inline ~_Dataflow() { this->Join(); }

 private:
  template <typename T>
  struct non_deducible {
    using type = T;
  };

  template <typename T>
  using non_deducible_t = typename non_deducible<T>::type;

  template <typename T>
  std::reference_wrapper<T> passed_by(T& t, std::true_type) {
    return std::ref(t);
  }

  template <typename T>
  T&& passed_by(T&& t, std::false_type) {
    return std::forward<T>(t);
  }

 public:
  template <class Ret, typename... Args>
  void AddFunction(Ret (*func)(Args...), non_deducible_t<Args>... args) {
    threads_.emplace_back(func, passed_by(std::forward<Args>(args),
                                          std::is_reference<Args>{})...);
  }

  inline void Join() {
    for (auto& t : threads_) {
      t.join();
    }
    threads_.clear();
  }

 private:
  std::vector<std::thread> threads_{};
};
#define HLSLIB_DATAFLOW_INIT() ::hlslib::_Dataflow __hlslib_dataflow_context;
#define HLSLIB_DATAFLOW_FUNCTION(func, ...) \
  __hlslib_dataflow_context.AddFunction(func, __VA_ARGS__)
#define HLSLIB_DATAFLOW_FINALIZE() __hlslib_dataflow_context.Join();
}  // namespace
#endif

}  // End namespace hlslib