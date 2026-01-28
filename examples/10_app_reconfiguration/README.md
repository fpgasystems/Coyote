# Coyote Example 10: Partial (application) reconfiguration with background services
Welcome to the tenth Coyote example! In this example we will cover how to load user applications on demand through partial reconfiguration. As with all Coyote examples, a brief description of the core Coyote concepts covered in this example are included below. How to synthesize hardware, compile the examples and load the bitstream/driver is explained in the top-level example README in Coyote/examples/README.md. Please refer to that file for general Coyote guidance.

## Table of contents
[Example Overview](#example-overview)

[Hardware Concepts](#hardware-concepts)

[Software Concepts](#software-concepts)

[Additional Information](#additional-information)

## Example overview
In this example, we cover how to synthesize multiple configurations (applications) for a single vFPGA, which can be loaded on demand. We will cover the hardware properties that need to be enabled to allow for swapping of individual user applications at run-time. In software, we will cover how to start a system-wide Coyote service which can load arbitrary user functions and schedule them for execution based on client requests. The service is also responsible for reconfiguring the vFPGA with the correct function bitstream.

<div align="center">
  <img width=600 src="img/app_reconfiguration.png">
</div>


**NOTE:** In Coyote, we make no assumptions when running multiple vFPGAs. That is, while vFPGA #0 is executing some operation, it's possible to reconfigure vFPGA #1 and vice-versa. The vFPGAs are completely independent and reconfiguring one has no impact on others.

**NOTE:** In this advanced tutorial we are focusing on dynamic loading of vFPGAs with a system-wide Coyote service that listens for client requests and executes them, ensuring the correct bitstream is loaded. If you are interested in simply reconfiguring an application at run-time, without the bells and whistles of scheduling and services, it can be done through the `reconfigureApp(...)` function from `cRcnfg`. The methods are similar to shell reconfiguration, which is explained in Example 5.

## Hardware concepts

### PR synthesis flow
To use partial (application) reconfiguration, in Coyote it is necessary to set `EN_PR` to 1 in the CMake configuration and specify the expected number of configurations (`N_CONFIG`), as shown in `hw/CMakeLists.txt`. Then, the vFPGAs can be loaded as previously. For example, the following configuration specifies two vFPGAs, each with two configurations:

```CMake
set(EN_PR 1)                    # Necessary to enable app reconfig
set(N_REGIONS 2)                # 2 vFPGAs       
set(N_CONFIG 2)                 # 2 configurations for each vFPGA

validation_checks_hw()

load_apps (
    VFPGA_C0_0 "vector_add"      # Config 0, vFPGA 0
    VFPGA_C0_1 "shifter"         # Config 0, vFPGA 1
    VFPGA_C1_0 "neural_network"  # Config 1, vFPGA 0
    VFPGA_C1_1 "hyper_log_log"   # Config 1, vFPGA 1
)

create_hw()
```

Additionally, a path to a floorplan with `N_REGIONS` pblocks needs to be specified through the `FPLAN_PATH`. An example floorplan path, alongside some guidance and tips, is given in `hw/example_fplan_u55c.xdc`.
Then, the hardware synthesis can be triggered as usual, using the commands `make project && make bitgen`. After its complete, 
Coyote will generate the following bitstreams:
1. The full Coyote bitstream, `cyt_top.bit`, which includes the static layer; used for initial programming of the FPGA
2. The partial shell bitstream, `shell_top.bin`, which holds the shell, pre-loaded with all the vFPGAs from config 0 (vector_add, shifter).
3. The partial app bitstreams, `vfpga_cX_Y.bin`, which holds the user application.

At run-time, it's possible to reconfigure either of the two vFPGAs with their respective application; i.e., vFPGA #0 can execute vector addition or neural network inference and vFPGA #1 can execute the shifter or HyperLogLog. Additionally, the two (or more) vFPGAs are independent; vFPGA #0 could be executing vector addition (from Config #0) whereas vFPGA #1 could be executing HyperLogLog (from Config #1) at the same time.

For more details on the hardware build process, check out the following [section in the documentation](https://fpgasystems.github.io/Coyote/intro/quick-start.html#building-the-hardware). In the next example, we describe how to link new user applications to an existing shell (in addition to for e.g., the four specified above).

## Software concepts
### Coyote functions (cFunc)
A Coyote service can define an arbitrary function, by specifying its unique ID (in this case `OP_EUCLIDEAN_DISTANCE`), the hardware bitstream (`app_euclidean_distance.bin`) for the function and the corresponding host-side software function. Each `cFunc` is linked to a Coyote thread, `cThread`, and optionally can take an arbitrary number of parameters of variable type. For example, in the following, we define a function for computing the Euclidean distance between two vectors. Note, first, the path passed to the function --- this is the path to partial bitstream of the vFPGA that was generated from the above mentioned synthesis build. Next, note, the body of the function implemented as a *C++ lambda function*. In general, a `cFunc` can have an arbitrary number of parameters of arbitrary types. In this case, we are passing three `int64_t` which represent the virtual addresses of vectors *a*, *b*, and *c*. Finally, the last parameter is the size of the vectors *a* and *b* (the vector *c* is simply a scalar). Finally, the function returns a float --- the time taken to compute the Euclidean distance (the answer is written to the memory location of `ptr_c`, and, hence also available after completion.)

```C++
std::unique_ptr<coyote::bFunc> euclidean_distance_fn(new coyote::cFunc<float, uint64_t, uint64_t, uint64_t, size_t>(
OP_EUCLIDEAN_DISTANCE, "app_euclidean_distance.bin",
[=] (coyote::cThread *coyote_thread, uint64_t ptr_a, uint64_t ptr_b, uint64_t ptr_c, size_t size) -> float {
    syslog(
        LOG_NOTICE, 
        "Calculating Euclidean distance, params: a %lx, b %lx, c %lx, size %ld", 
        ptr_a, ptr_b, ptr_c, size
    );
    auto begin_time = std::chrono::high_resolution_clock::now();

    // Cast uint64_t (corresponding to a memory address) to float pointers
    // Note, how there is no memory allocation in this function - these memories are allocated by the client
    // and passed to the function as memory addresses (pointers)
    float *a = (float *) ptr_a;
    float *b = (float *) ptr_b;
    float *c = (float *) ptr_c;
    
    // Run the Euclidean distance operator on the vFPGA; similar to HLS Vector Addition from Example 2
    coyote::localSg sg_a = {.addr = a, .len = (uint) (size * sizeof(float)), .dest = 0};
    coyote::localSg sg_b = {.addr = b, .len = (uint) (size * sizeof(float)), .dest = 1};
    coyote::localSg sg_c = {.addr = c, .len = sizeof(float), .dest = 0};
    
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_a);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_READ,  sg_b);
    coyote_thread->invoke(coyote::CoyoteOper::LOCAL_WRITE, sg_c);
    while (
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_WRITE) != 1 || 
        coyote_thread->checkCompleted(coyote::CoyoteOper::LOCAL_READ) != 2
    ) {
        std::this_thread::sleep_for(std::chrono::nanoseconds(50));
    }
    
    coyote_thread->clearCompleted();

    auto end_time = std::chrono::high_resolution_clock::now();
    double time = std::chrono::duration_cast<std::chrono::microseconds>(end_time - begin_time).count();
    return time;
}
));
```
**IMPORTANT:** If the function runs as part of a background service (next section), prints using `std::cout` or `printf` should be avoided as they can crash the background service and make little sense (there is not stdout for a background service). Instead, `syslog` should be used.

**IMPORTANT:** Note, how the pointer to vectors *a*, *b* and *c* are passed here. However, also note how there aren't any "pure" C++ operations on these arrays (e.g., addition, prints etc.). The reason for this is that it would cause a segmentation fault. If the arrays are allocated by a different process, as it is the case in this example (the client allocates the arrays and passes a pointer to the server), they do not share a memory space. The only reason Coyote operations can be performed on these arrays is because Coyote implements a memory mapping in its driver. To do so, it needs the client's process ID, which is sent from the client to the server during set-up. If you would like to extend this example, performing some operation on the server CPU and some on the FPGA, it is possible by setting up some shared memory between processes. There are several abstractions and libraries in C++ that can do this.

### Coyote service (cService)
Coyote implements a system-wide background service, which can register functions (as explained above) and accept connections from clients. It also uses the Coyote scheduler (`cSched`) which schedules the execution of client tasks to the above functions and handles reconfiguration as needed. Client tasks can be processed either in a (1) first-in, first-out manner, triggering reconfiguration whenever needed, or (2) by minimizing reconfigurations (due to the latency cost), so that all the tasks that can be executed on the current bitstream, are executed first.

The service can be created as follows:
```C++
// Parameters are:
// Name of the service, used for creating the Linux socket for connections
// Remote: true or false
// vFPGA linked to the service
// Device, for systems with multiple FPGAs (default is 0)
coyote::cService *cservice = coyote::cService::getInstance("pr-example", false, DEFAULT_VFPGA_ID, DEFAULT_DEVICE);
```

Then, a function can be added to the service as follows:
```C++
cservice->addFunction(std::move(cosine_similarity_fn))
```
**NOTE:** The function should have a unique ID and a correct bitstream path. If not, the service will not add the function.

Finally, the service can be started with:
```C++
cservice->start();
```
which starts the background daemon, scheduler and sockets for listening to client connections.

### Connecting to a service & submitting tasks (cConn)
Clients can connect to the service through the utility class `cConn`, as shown below:
```C++
// The socket can be derived from the service name and should match
// /tmp/coyote-daemon-dev-{DEVICE_ID}-vfid-{VFPGA_ID}-{SERVICE_NAME}
coyote::cConn conn("/tmp/coyote-daemon-dev-0-vfid-0-pr-example"); 
```

A task can be submitted through the following:
```C++
/** 
 * Submit task to the background daemon and wait until completed; returns the time taken
 * The first parameter is the operation to perform (0 for Euclidean distance, 1 for cosine similarity)
 * The next three parameters are the pointers to the input vectors (a, b) and note how the other
 * parameters (and the function template) matches the function signature defined in the server code
 * The function returns a float, the time it takes to execute the operation in microseconds as measured by the Coyote daemon
 */
float time = conn.task<float, uint64_t, uint64_t, uint64_t, size_t>(operation, (uint64_t) a, (uint64_t) b, (uint64_t) c, size);
```
Note, how the task templates match the function signature defined on the server. If they didn't, the server would throw an exception and wouldn't process the task.

**NOTE:** This example covers synchronous/blocking tasks. Asynchronous/non-blocking tasks can be achieved with the `iTask` function and polling for completion, both of which are documented in `cConn.hpp`.

## Additional information

### Running the example

To run this example, the following steps are necessary:
1. The hardware must be synthesized, as usual. Note, however, that this example is meant for running on the Alveo U55C, as the floorplan is platform-specific. It may also work for the U280 but unlikely to work for other platforms. For other platforms, one should provide a suitable floorplan, similar to the one provided in this example.
```bash
cd hw/
mkdir build_hw && cd build_hw
cmake ../ -DFDEV_NAME=u55c
make project && make bitgen
```

2. The FPGA should be programmed with the top-level Coyote bitstream, `hw/build_hw/bitstreams/cyt_top.bit`. 

2. The software can be compiled similar to the RDMA example, one for the server and one for the client. Two CMake builds have to be triggered to obtain the correct executables. In order to build the server code, one needs to specify `-DINSTANCE=server`, while a build of the client software is specified with `-DINSTANCE=client`:
```bash
cd sw/

mkdir build_server && cd build_server
cmake ../ -DINSTANCE=server && make

cd ../
mkdir build_client && cd build_client
cmake ../ -DINSTANCE=client && make
```

3. The partial application bitstreams must be renamed and copied to the software build folder, so that the service can load them when started. Alternatively, one can change the path in the server code to point to the original bitstream location. Therefore (assuming the hardware was built in `hw/build_hw/`), the following is recommended:
- Copy from `hw/build_hw/bitstreams/config_0/vfpga_c0_0.bin` to `sw/build_server/app_euclidean_distance.bin`
- Copy from `hw/build_hw/bitstreams/config_1/vfpga_c1_0.bin` to `sw/build_server/app_cosine_similarity.bin`

4. Launch the server as a background task by:
```bash
cd sw/build_server
./test
```

5. After the server started, you can start the client in the same terminal by:
```bash
cd sw/build_client
# 1 for Euclidean distance and 0 for cosine similiarity
./test -o <0|1>
```

**NOTE:** This example assumes the server and client are on the same node. We are working on bringing back support for remote connections to the server.

When done with the experiment you will have to send a sigint signal to the server to stop it. Do this for example using:
```bash
pgrep -u $USER -l test
kill -SIGINT <process id of server>
```
or even quicker:
```bash
pkill test
```


### Command line parameters
- `[--size | -s] <int>` Vector size (default: 1024)
- `[--operation | -o] <bool>` Target operation (similarity metric): Euclidean distance (0) or cosine similarity (1) (default: 0)
