# Python unit testing framework

This is the documentation of the Coyote, Python unit testing framework. The next section will introduce some pre-requisites that are needed to use the framework. Afterward, the offered functionality is described.

## Repository structure

### Unit test directory
The framework is built with the assumption, that you are using coyote as a git sub-module inside a repository that contains your design to test.

By default, it is assumed that all your unit-tests are inside the a directory called ```unit-tests``` in the root of your repository. If this should not be the case, define the following variable in your CMakeLists.txt to change the directory setting:

```cmake
set(UNIT_TEST_DIR "${CMAKE_SOURCE_DIR}/unit-tests")
```

Note that the path should be absolute. Please delete and re-build your sim project after the change.

### Python imports

The functionality of the framework is provided inside the ```coyote_test``` directory inside your build folder. E.g. if you build your sim make target inside ```build_hw```, you can import the framework from ```build_hw/coyote_test```. If this directory does not exist, you might have created your sim target using a older version of Coyote. If thats the case, please delete ```build_hw``` and re-build it to get all the needed dependencies for the framework.

In order for Python to know where to find the framework, we need to add the ```build_hw``` path to the ```PYTHONPATH``` environment variable. There are several ways to do this, depending on your environment.

If you want to use intellisense in your IDE, you might also have to add the ```coyote/sim``` path to your ```PYTHONPATH``` environment. The reason is that, due to technical reasons, the python module inside ```build_hw/coyote_test``` re-exports all definitions from ```coyote/sim```, which cannot always be properly resolved by a intellisense implementation. If your coyote sub-module is not in the ```coyote``` directory, you need to adjust this path.

#### Example: VSCode
If you are using VSCode with the Microsoft supplied Python extensions, you can create a ```.env``` file in the root of your repository with the following content:

```console
PYTHONPATH=build_hw:coyote/sim
```

This adds both the ```build_hw``` directory and the ```coyote/sim``` directory to your PYTHONPATH.

### Other environments

If you are using other environments, please look into the documentation of your IDE on how to properly add paths to the ```PYTHONPATH``` environment variable.

## Framework

The framework is build on top of the Python [unittest](https://docs.python.org/3/library/unittest.html) Unit-testing framework.

The framework offers the following, high level features:

- Provide high-level, convenience methods to quickly define the expected in & output for a test case
- Allow fine-grained control via direct access to the simulation wire-protocol
- Handle all the needed Vivado steps for you. There is no need to open Vivado by hand or to interact with Vivado directly in any way.
- "Smart" compilation handling. The framework will detect changes in your project and only re-compile when needed. This reduces run-time for tests significantly.
- Create a signal dump that can be opened with Vivado or third-party tools to allow debugging failed test cases.
- Integration into common unit-testing tooling via Python [unittest](https://docs.python.org/3/library/unittest.html). E.g. [Test explorer in VSCode](https://code.visualstudio.com/docs/debugtest/testing#_automatic-test-discovery-in-testing-view).
- Reconfiguration of your design via custom ```fpga_top.svh``` modules and defines that can control how your design behaves to trigger specific testing conditions or only test certain modules.

> [!tip]
> If you need to, you can manually open the simulation projcect with Vivado project at ```vivado build_hw/sim/test.xp```

> [!tip]
> If the compilation/elaboration of the design fails during simulation, the testing framework will automatically open the error files for you IF you are using VSCode!

## Test cases

The framework offers two classes that can be inherited from to define a test case ```FPGATestCase``` and ```FPGAPerformanceTestCase```. The first class should be used for correctness tests and the second one for performance tests. However, most functionality is shared between both. The following explains the functionality step-by-step.

### Minimum viable test

The following example declares a minimum, viable test. The test-cases defines a INT32 input on stream 0, and sets an expected output on stream 0. It then triggers a blocking simulation of your design via the ```simulate_fpga()``` call and, lastly, asserts that the output was as expected.

```python
from coyote_test import fpga_test_case

class SomeFPGATestCase(fpga_test_case.FPGATestCase):

    # Method that gets executed once per test case
    def setUp(self):
        return super().setUp()
    
    # Overwrite of the parent classes simulation method.
    # Can be used to implement common behavior between tests
    def simulate_fpga(self):
        return super().simulate_fpga()

    # Example test case, following the AAA-pattern.
    # The test case shows all the methods needed to 
    # define tests and invoke the simulation.
    def some_test_case(self):
        # Arrange
        self.set_stream_input(0, Column("input", ColumnType.SIGNED_INT_32, [1, 2, 3]))
        self.set_expected_output(0, Column("output", ColumnType.SIGNED_INT_32, [1]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
```

```set_stream_input```, ```set_expected_output```, ```simulate_fpga```, and ```assert_simulation_output``` are convenience methods. In the background, they will do the following for you:

- Acquire virtual memory in the simulation to fit your input.
- Transfer the input data to the test-bench into the previously acquired memory.
- Acquire virtual memory in the simulation to fit your output.
- Trigger a Coyote LOCAL_WRITE transfer via the HOST STREAM that sends the input to the FPGA.
- Trigger a Coyote LOCAL_READ transfer via the HOST STREAM to read the output of the expected length to the allocated memory.
- Starts the simulation of your design in a background thread. This starts Vivado, compiles your design, etc.
- Perform a blocking wait using a ```checkCompleted``` call to wait for the LOCAL_READ transfers to finish.
- Transfer the memory for the completed LOCAL_READS to Python.
- Check that the received output matches the one specified by you via the ```set_expected_output``` call.

As you may notice, all of these steps directly map into functionality of the Coyote client library, or more specifically the cThread! The test bench models all of this behavior, including a virtual memory system! If you want, you can directly interact with the test bench interfaces instead of using the methods described above. See the description further down.

> [!tip]
> If you are unfamiliar with the Coyote concepts like transfers and completion, check out the [tutorials](https://github.com/fpgasystems/Coyote/tree/tutorial/examples).

Before we continue to discuss more advanced functionalities of the framework, three things should be mentioned:

1. Timing randomization

The test bench supports timing randomization. This means, that the inputs for your design and the outputs from your design will be will be read/written with a randomized delay. This is a very useful feature to detect common synchronization issues, in particular between the tvalid and tready signals of the AXI4 interface. By default, this randomization is therefore enabled for all ```FPGATestCase``` instances. If you want to disable the randomization, you can do so by setting the ```_disable_input_timing_randomization``` property to ```True```.

2. Simulation time

By default, the simulation of your design is run for at most ```4ns```. The reason for this default is that without a fixed, maximum runtime, your design will run forever when there are bugs. For example, if less than the expected output is provided, your design will simply hang since Coyote will wait for the LOCAL_READ to finish. To prevent this scenario, the simulation will terminate after the mentioned ```4ns```. However, this might not be enough time to execute all logic depending on the complexity of your design and the input/output size you expected.

Therefore, you can change this runtime via the ```overwrite_simulation_time``` function. This also allows you to let the design run till it finished itself, e.g. when all expected output has been provided to coyote.

3. Interacting with the simulation

In general, one can interact with the simulation/test bench as if it where a real device. E.g. one can start transfers and then do blocking check_completed calls in the main thread to wait for the transfers to finish. However, due to the nature of the simulation some caution has to be placed in handling blocking calls. Especially, one need to know that the simulation is only running while ```simulate_fpga``` is begin called. Especially, no blocking calls can be made before or after this call since they will just hang-up the test case. While relying on the provided convenience functions, everything should behave as expected as ```simulate_fpga``` is the only blocking call. However, if you want to e.g. read a register value, more caution has to be put into to the test case. See details below at ```How do I interface directly with the test bench instead of using the provided convenience methods?``` for the threading model of the simulation to understand this behavior.

The following describes more advanced concepts shared by both testing classes. Afterward, we will also describe the ```FPGAPerformanceTestCase```.

### How can I write and read CSR register?

Use the ```write_register``` and ```read_register``` functions!

Caution: Reading a register is blocking and a stop_event can be supplied!

### How do I send data using a different stream than HOST?

Both the ```set_stream_input``` and ```set_expected_output``` provide a parameter that can be changed to send data, e.g. via the CARD stream. Note: Not all streams are supported by the test bench yet.

### How can I debug a test case that is failing?

To debug, there are two tools you can use:

1. A signal dump. This dump is automatically generated for **all** signals in the simulation and stored at ```/unit-tests/sim_dump.vcd```. (or at another path if you use a different unit test directory). See below on how to use the dump.
2. A log file. When a test fails, a python error will be thrown that contains the whole simulation text output, including any potential ```$display``` statements used in the code. Additionally, a log file with the same output can be written to disk by calling the ```write_simulation_output_to_file()``` method on the test case. You can also set the ```_debug_mode``` property to ```True``` in your test class, which will write all output immediately. Lastly, there is the ```_verbose_logging``` property, which will enable more detailed logs, if set to ```True```.
3. A diff will be created for you in your unit-test folder under ```/diff```. This folder will contain several file pairs per stream. Each pair contains the actual und expected output of the stream. The different pairs are created to interpret the binary data in the most common data types like int32, int64, and floats to help you compare the values directly instead of needing to work on the binary level. You can create a diff between two files of the same type using common diff tools. E.g. in VSCode, mark both files, do a right-click and select "Compare Selected".

If you are using VSCode, the simulation signal dump can be directly viewed in VSCode using the [VaporView](https://github.com/Lramseyer/vaporview?tab=readme-ov-file) extension. Simply install the extension and open the ```sim_dump.vcd```file. You can then select the signals to display:

![alt text](img/vapor_view.png "Vapor View Example")

If you want to rerun the test case, you can reload the ```.vcd``` file afterwards by right-clicking on the VaporView and selecting 'Reload File'. This will keep all your signal selections!

![alt text](img/vapor_view_reload.png "Vapor View Reload")

You can also safe/load the selected signals by right-clicking and selecting the VaporView settings options. By default, the settings file at ```unit-tests/vapor_view.json``` is ignored.

To restrict, which signals are dumped by the testing infra, you can specify a path via the ```_test_sim_dump_module``` variable. See the filter test cases and description inside the ```fpga_test_case.py``` file for further info.

VaporView has other great features! See the Github repository linked above for more infos.

### I need to convert my own data to a bytearray, which byte order should I use?

All data should always be sent via little-endian.
You can import the BYTE_ORDER constant from coyote_test like so:

```python
from coyote_test import constants

BYTE_ORDER = constants.BYTE_ORDER
```

which is set to "little"!

### When is my code re-compiled? How can I force a re-compilation?

You code is re-compiled if one of the following is true:

- Any file changed inside the source directory of your VFPGA, the coyote test bench, or your alternative vfpga_top
- Your alternative vfpga_top changed. E.g. to a different file or the default one in your source code
- Your SystemVerilog defines have changed. E.g. define values has been altered, new defines have been added, or defines where removed. Note that some properties of the test framework like the input randomization are also controlled via defines. Therefore, changing those will also trigger a re-compilation.

The current compilation state is saved inside your build folder in the ```sim``` directory in a file called ```.last_change_time```. Deleting this file, or the whole build folder, will always trigger a re-compilation of your source code.

Whether code was re-compiled or not can be seed in the log files. You will see a log message stating that ```Recompilation is required.```.

### How to use a different vpfga_top.svh for your test case

If you want to replace the default ```vpfga_top.svh``` file for your test case from the default inside ```/src```, you can specify the ```_alternative_vfpga_top_file``` property. The path to the file should be relative to your unit-test folder.

> [!tip]
> Testing specific modules instead of your whole design can significantly reduce compilation times and therefore make the dev-test-fix loop much quicker.

### How can I change properties of my design (like parameter, or localparam) to test different scenarios?

The framework supports setting SystemVerilog defines for a test case. This can be done via the ```set_system_verilog_defines``` method. See the method documentation on how to use this in your design.

### How do I interface directly with the test bench instead of using the provided convenience methods?

The wire protocol of the test bench is implemented in to so-called ```io-writer```. One can get a instance of this class via the ```get_io_writer``` method. This allows you to call the Coyote methods directly on the simulation. E.g. you can allocate memory, trigger transfers, read registers, etc.

> [!tip]
> The virtual memory implementation in the io-writer includes bounds checks! This is true for memory written/read in python and also for memory written to by the FPGA or via a transfer. Should any access be out of bounds, you will get an error.

However, handling these calls correctly can be tricky. Therefore, the following gives a short introduction into the threading model of the simulation.

In general, there are four threads:

1. The main thread of the test case. This thread executes your test code!
2. A background thread that runs Vivado and the simulation. This thread supplies tcl commands to vivado via the interactive tcl mode and checks the produced output for errors. 
3. A background thread that supplies input to the simulation. Any non blocking call (e.g. ```invoke_transfer```) is put into a thread safe queue that is read from this thread and then written to the simulation. The communication with the simulation is done via named unix pipes.
4. A background thread that reads output from the simulation. This works in a similar way to the input thread: The thread constantly waits for output from the simulation, parses it, and puts results into queues. These queues are waited for by the main thread, e.g. during a blocking call like ```block_till_completed```.

What is important to understand is when these threads are running. The IO threads (3 & 4) are started immediately with the simulation. However, the Vivado thread is only started once ```simulate_fpga()``` is called. The default implementation of ```simulate_fpga``` starts the thread, does a blocking wait for the completion of LOCAL_READS triggered via the ```set_expected_output``` method, and then joins the thread.

Alternatively, one can start the thread via ```simulate_non_blocking``` and join the thread via ```finish_fpga_simulation```. The start method returns a event. This event is thrown when the Vivado thread terminates. This can be because it finished or threw an error. All non blocking methods accept this event as a parameter to terminate them should vivado quit unexpectedly. This can, for example, happen when your design fails to compile.

If you want to perform any blocking calls yourself, you need to start the simulation via the methods mentioned above, perform your logic, and then join the simulation once you are done! However, there are two more details to consider with this approach:

1. Closing the simulation

As mentioned above, the communication with the test bench is done via named unix pipes. The test bench continuous to run until the input pipe receives a EOF. Until then, new commands can be received and, therefore, the bench cannot terminate.

This means, test cases need to explicitly mark the input as done. This is usually done in the ```simulate_fpga()``` method. However, with the two methods above, you need to do this yourself whenever all input commands have been sent. To do this, simply call the ```all_input_done``` method on the IO writer.

2. Interrupts

The io_writer also allows you to register interrupt callbacks. Those are python methods that will be called when the FPGA triggers a interrupt on the host. These callbacks are executed within the context of the output background thread. The io writer was specifically designed to allow you to execute most methods from within a interrupt handler. However, you CANNOT execute blocking functions! The reason is that those blocking functions need the output thread to make progress. However, this thread is blocked by executing the interrupt itself!

If you need to execute blocking calls from within a interrupt, you can spawn a new thread from the interrupt, which will execute the blocking calls. Here is a example, using the ```SafeThread``` class provided by coyote_test:

```python
def test(self):
    # Arrange
    def read_csr_callback(stop_event):
        # Read the CSR value
        self.required_cycles = self.get_io_writer().ctrl_read(
            NamedFPGAConfiguration.REQUIRED_CYCLES.value
        )
        # Mark all input as done
        self.get_io_writer().all_input_done()

    def read_csr_callback_entry():
        # Needs to spawn its own thread to we can perform blocking
        # IO operations. Otherwise, reading the output is blocked!
        self.thread = SafeThread(read_csr_callback)
        self.thread.start()

    self.get_io_writer().register_interrupt_handler(read_csr_callback_entry)

    # Act
    self.simulate_fpga()
    self.thread.join_blocking()

    # Assert
    self.assert_simulation_output()
```

### How do I assert output without using the set_expected_output method?

If you cannot use the ```set_expected_output``` method, e.g. because you don't want do a transfer from the host side, you can set the expected output via the ```set_expected_data_at_memory_location``` function. This configures which output data is expected at which memory location and is then used by the ```assert_simulation_output``` function to compared the actual memory values with the expected ones.

## Performance tests

While the ```FPGATestCase``` class is perfect for determining correctness of your design, it is not suited for estimating the design's performance. The reasons are as follows:

- By default, the unit-tests enable in & output timing randomization. This is great to find common issues like tready/tvalid synchronization and determine correctness but not for determining the performance of your design.
- Performance test cases need to fulfill certain properties to make the measured performance correct.

To understand why certain properties are needed, we need to understand how the performance tests are implemented in the framework. Performance here refers to two properties:

1. Latency: How many cycles does it take from the input of a data beat till the corresponding output is received?
2. Throughput: How many cycles does the design need per data beat once the pipeline is full, i.e. without the latency

As the framework cannot have a understanding of your design, performance tests are implemented in a general way:

The test bench creates log messages whenever a batch is send or received from the design. These messages contain a timestamp that can be translated into a cycle.

As a consequence, a performance test should adhere to the following properties to make it accurate:

1. The first input batch needs to produce a output batch. This is because the test bench records the first cycle in which output is received and this is used to calculate the latency. Otherwise, some cycles which actually do processing will be treated as latency cycles and your numbers wont be correct!
2. The last input batch needs to produce a output batch. This is due to the same reasons as above: If the design produces the last output before the last input has been processed the number of total needed cycles will not be correct.

When adhering to these principles, one can write Performance tests using the ```FPGAPerformanceTestCase``` class in the same way as any other FPGA test case. The latency and throughput in cycles will be automatically calculated and printed with the test output. Additionally, one can assert the performance of the design as follows. See the following example:

```python
from coyote_test import fpga_performance_test_case

class SomeFPGAPerformanceTestCase(fpga_performance_test_case.FPGAPerformanceTestCase):

    # Example test case, following the AAA-pattern.
    # The test case shows all the methods needed to 
    # define tests and invoke the simulation.
    def some_test_case(self):
        # Arrange
        self.set_stream_input(0, Column("input", ColumnType.SIGNED_INT_32, [1, 2, 3]))
        self.set_expected_output(0, Column("output", ColumnType.SIGNED_INT_32, [1]))
        self.set_expected_avg_cycles_per_batch(0, 1.0)
    
        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
```

The ```set_expected_avg_cycles_per_batch``` function can be used to set a performance expectation. One batch here refers to one data beat. E.g. in the example above we expect each data beat to take one cycle to be processed for the stream 0. This performance is automatically verified in the ```assert_simulation_output``` function. When using the ```FPGAPerformanceTestCase``` class this function does not only validate the correctness of the output but also the expected performance goals.

The output produced by a test case will look like this:

```console
20:42:32; FPGAPerformanceTest; SIMULATION PERFORMANCE
20:42:32; FPGAPerformanceTest; Stream [0]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     118 cycle latency
20:42:32; FPGAPerformanceTest; Stream [1]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     130 cycle latency
20:42:32; FPGAPerformanceTest; Stream [2]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     131 cycle latency
20:42:32; FPGAPerformanceTest; Stream [3]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     132 cycle latency
20:42:32; FPGAPerformanceTest; Stream [4]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     133 cycle latency
20:42:32; FPGAPerformanceTest; Stream [5]       3840 bytes      60 data beats   60 cycle send   60 cycle recv   1.00 avg cycle per batch        1.00 avg cycle per batch with sending delay     134 cycle latency
```

It states the overall size of the input, how many cycles where spent reading the input (send), how many cycles where spent reading the output (recv) and which throughput this achieves, with and without sending delays. Lastly, the latency per stream is given!