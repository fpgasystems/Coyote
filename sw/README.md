# Coyote software

## Overview
The Coyote software stack is a vital component of Coyote, providing a high-level interface for interacting with the Coyote shell in hardware. For example, the software allows users to seamlesly start data movement, set and read control registers, trigger reconfiguration etc. Additionally, it provides a set of advanced features which can load Coyote as a system-wide service to which arbitrary tasks can be submitted. The software is written in C++, enabling high performance and low-level control as well as high levels of abstraction. Broadly speaking, the software stack consists of the following abstractions:

- **Coyote threads**: The `cThread` is the core component of the Coyote software, facilitating interaction with a single virtual FPGA (vFPGA). The `cThread` class enables operations such as memory mapping, DMA commands, and vFPGA control. Additionally, it provides utility functions, for e.g., debug prints and out-of-band RDMA QP exchange. Finally, it provides a locking mechanism, ensuring the current Coyote thread is the only one executing on the vFPGA, even when considering `cThreads` from other processes. The `cThread` is introduced in detail in Examples 1, 2, 3 and 4. Advanced features such as multi-threading and RDMA networking are shown in Examples 8 and 9, respectively.

- **Reconfiguration**: The Coyote software stack supports partial reconfiguration of virtual FPGAs (vFPGAs), as well as the entire shell. The reconfiguration is handled through the ```cRcnfg``` class which abstracts away the complexity of bitstream loading and driver interaction. Reconfiguration functionality is shown in Example 5.

- **Functions, tasks and scheduling**: Beyond the above-mentioned core abstractions, Coyote introduces advanced features of user-defined functions and tasks which can be dynamically loaded through the scheduler. First, the `cFunc` class provides a high-level abstraction of a user-defined function, consisting of a path to an application (vFPGA) bitstream and the corresponding software-side code (leveraging `cThreads`) to interact with the vFPGA. For example, a `cFunc` can be created to point to a file containing an encryption bitstream and a standard C++ function which would set the encryption key and proceed to submit some text for encryption. Then multiple tasks (`cTask`) can be submitted to this function, each represnting a different execution of the function (for e.g., with different source texts or encryption keys). The tasks are managed by the scheduler (```cSched```), which contains a registry of all the function and a list of outstanding tasks. Imprtantly, the scheduler can hold multiple functions, each of which can require a different bitstream. Therefore, the scheduler is also responsible for reconfiguring the vFPGA, as required. Currently, two scheduling policies for tasks exist: first-in, first-out and minimize recinfigurations, for which all outstanding tasks linked to the current bitstream are executed first, before reconfiguring. The latter is particularly important as partial FPGA reconfiguration incurs non-negligible latency overhead. The concept of functions, tasks and scheduling is introduced in Example 10.

- **Coyote background service**: Further raising the level of abstraction, Coyote introduces the `cService` class, which launches a system-wide background service that can hold arbitrary functions. The background services builds on top of `cSched` and can accept client connections and tasks. On the client side, the interaction is simplified through the `cConn` class which can connect to a Coyote service and submit tasks for a certain function/operator. For example, the `cService` instance may hold two functions, each representing a type of machine learning model. Then, the client can connect and submit a request to use on of the models through `cConn`, only needing to pass the model (function) identifier and the input data, requring no further interaction with Coyote. In a way, this model resembles Function-as-a-Service. Examples of using the Coyote background service is shown in Examnple 10.

## Using the software

**Compilation**: To compile the software, CMake >= 3.5 and a compiler support C++17 is required. Coyote can be included as a CMake dependency either as a git sumbodule with `add_subdirectory` or from a system-wide installation using the CMake's standard `find_package`. Following is a brief explaination of the two approaches:

- `add_subdirectory`: You should use this CMake directive if you're including coyote as a Git submodule for your project. This is a common scenario if you're building an hardware design and a software library to go alongside it. In this case, the most convenient way to keep the Coyote dependency aligned with the hardware side is to include it in CMake directly from the Coyote source code that you already have in your project. To do this, you can use the [`add_subdirectory`]() driective, pointing it to the `sw` folder in the Coyote project. Here's an example for a typical project structure:
    ```
    project/
    |- coyote/
    |- ...
    |- software/
       |- CMakeLists.txt
       |- src/
    ```
    In that `CMakeLists.txt`, you would add the Coyote dependency as follows
    ```cmake
    add_subdirectory(../coyote/sw coyote)
    ```
    If you want to include the Coyote simulation version of the library, follow the instructions in the [simulation documentation](../sim/README.md).
- `find_package`: You should use this CMake directive if you're including coyote as an external dependency, installed manually or via your system package manager. This is the preferred method when working on a third-party project that doesn't want to pull in Coyote as a git submodule. Please, refer to the installation section below for how to install Coyote system-wide or in a chroot. In this case, you can simply place this CMake directive in the project's `CMakeLists.txt`:
    ```cmake
    find_package(Coyote)
    ```
    You may also use the `CoyoteSimulation` package to run the software against xsim, as described in the [simulation documentation](../sim/README.md).

In both scenarios, after the CMake library has been included, you should link your target against Coyote with the following rules:
```cmake
target_link_libraries(<target> PUBLIC Coyote)
target_include_directories(<target> PRIVATE ${COYOTE_INCLUDE_DIRS})
```

Some applications which include Coyote library can be found in any of the examples. Finally, the software can be built with debug prints, which can be enabled through the flags `VERBOSE_DEBUG_1` (for local operations), `VERBOSE_DEBUG_2` (for reconfigurations) and `VERBOSE_DEBUG_3` (for remote operations). Additionlly, when using the Coyote service and scheduler, debug prints and warning can be found in syslog.

**Installation**: You can compile and install Coyote in your system or in a chroot using the following commands (assuming you're in the sw/ folder):
```bash
$ mkdir build && cd build
$ cmake ..
$ make install
```

When running `make install` you can provide a custom chroot directory where the library should be installed. For example, when you're on the HACC cluster, you will not be able to install the library in `/usr`, so you may wish to install it in a chroot and then point your other projects to look for libraries under that path. Here's an example of how you would do that:
```bash
$ mkdir path/to/chroot
...
# when installing Coyote
$ make DESTDIR=path/to/chroot install
...
# when compiling another project that should link against Coyote
$ cmake -DCMAKE_PREFIX_PATH=path/to/chroot <path>
```
This way, the project will _also_ look for libraries in `path/to/chroot` and find the Coyote library to link against. Note that if you can install the library to a common prefix (i.e., `/`, `/usr`) you will not need to specify the `MAKE_PREFIX_PATH` option.

**Documentation**: All headers files (in `include`) contain extensive documentation about the functions and variables in standard Doxygen form. This documentation should be the first point of reference about the software. The source files (`src`) contain less comments. Harder-to-understand functions and complex code segments include comments, but Coyote's approach is to write smaller, self-contained functions that can be fully explained by the docstring in the accompanying headers.
