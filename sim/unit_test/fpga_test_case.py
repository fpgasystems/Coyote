######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

import os
import unittest
from typing import Union, List, Optional, Dict
from io import StringIO
import threading
import logging
import sys
import array
import fcntl
import termios
import time

from .process_runner import ProcessRunner, VivadoRunner
from .simulation_time import SimulationTime, SimulationTimeUnit, FixedSimulationTime
from .fpga_stream import Stream, StreamType
from .constants import (
    MAX_NUMBER_STREAMS,
    UNIT_TEST_FOLDER,
    SIM_OUT_FILE,
    VFPGA_SOURCE_FOLDER,
    N_REGIONS,
    SRC_V_FPGA_TOP_FILE,
    TEST_BENCH_FOLDER,
    CLOCK_PERIOD,
    VIVADO_BINARY_PATH,
)
from .fpga_register import vFPGARegister
from .io_writer import SimulationIOWriter, CoyoteOperator, CoyoteStreamType
from .utils.exception_group import ExceptionGroup
from .utils.thread_handler import SafeThread
from .output_comparison import OutputComparator


class ExpectedOutput:
    """
    Small wrapper class to describe expected output at specific
    memory locations
    """

    def __init__(
        self,
        vaddr: int,
        output: bytearray,
        length: int = -1,
        stream: Union[int, str] = None,
        stream_type : StreamType = None
    ):
        """
        length = Optional. By default (-1) its the length of output.
                Can be specified to ensure length data is read in memory
                if the memory might contain more data than is expected
        """
        self.vaddr = vaddr
        self.output = output
        self.length = len(output) if length == -1 else length
        self.stream = stream
        self.stream_type = stream_type

    def get_vaddr(self) -> int:
        return self.vaddr

    def get_expected_output_data(self) -> bytearray:
        return self.output

    def get_length(self) -> int:
        return self.length

    def get_stream(self) -> Optional[Union[int, str]]:
        return self.stream

    def get_stream_type(self) -> Optional[StreamType]:
        return self.stream_type


class FPGATestCase(unittest.TestCase):
    """
    Base class with shared functionality for all FPGA-based tests.
    Unfortunately, there are sources shared between the tests. Therefore,
    tests have to be run one at a time.
    """

    # By default, the vfpga_top.svh inside your source folder will be used.
    # However, when testing specific (sub) modules, one might need to change
    # the wiring for some test cases. Therefore, this vfpga_top.svh can be
    # overwritten by setting a path relative to the unit_test folder
    # at this variable.
    # E.g. if your unit-test folder has a file called test_wireing.svh
    # you can set alternative_vfpga_top_file to 'test_wireing.svh'
    alternative_vfpga_top_file = None
    # Whether to disable input randomization (good for correctness)
    # In favor of getting exact performance measurements (latency & cycles)
    # This property is mainly used by the FGPAPerformanceTestCase.
    disable_input_timing_randomization = False
    # A specific module to filter the sim vcd dump by.
    # Without specifying this value, the dump will contain all signals in tb_user.
    # With this value, the signals can be further restricted.
    # E.g. if your vpga_top.svh contains a module instantiation called 'db_pipeline',
    # which contains a module called 'inst_filter', the filter could be like this:
    # db_pipeline/inst_filter
    test_sim_dump_module = ""
    # Whether debug mode is enabled.
    # In debug mode, the following is done:
    #   - all log output is printed immediately
    #   This allows one to debug the test behavior
    debug_mode = False
    # Whether verbose logging is enabled.
    # Enabling this will produce significantly
    # more detailed logs in the test bench.
    verbose_logging = False

    def __init__(self, methodName="runTest"):
        super().__init__(methodName)

    #
    # Private methods
    #
    def _is_running_inside_vscode(self):
        return "VSCODE_CWD" in os.environ

    def _try_to_open_vivado_log_file_on_sim_failure(self, output_lines):
        if not self._is_running_inside_vscode():
            return

        log_files = ["xvlog.log", "elaborate.log", "xvhdl.log"]

        for line in output_lines.split("\n"):
            for log_file in log_files:
                if log_file in line:
                    # Split the string, find the path to the log_file with the format (e.g. for xvlog): '{PATH}/xvlog.log'
                    path_line = list(
                        filter(lambda part: part.endswith(log_file), line.split("'"))
                    )
                    for line in path_line:
                        if os.path.exists(line):
                            logging.getLogger().info(
                                f"NOTE: Opening error file {log_file} for you in current VSCode window"
                            )
                            ProcessRunner().try_open_file_in_vscode(line)

    @classmethod
    def _get_vfpga_top_file_path(cls) -> str:
        """
        Returns the path to the vfpga_top file to use for this test case
        """
        if cls.alternative_vfpga_top_file is not None:
            return os.path.join(UNIT_TEST_FOLDER, cls.alternative_vfpga_top_file)
        return SRC_V_FPGA_TOP_FILE

    def _run_simulation(self, stop_event: threading.Event):
        """
        Private method that runs the simulation
        Is called in a thread to ensure the simulation can run non-blocking
        """
        # Note: The stop_event is ignored since simulation always needs to run to the end
        logging.getLogger().info("STARTING SIMULATION")
        success = VivadoRunner().run_simulation(
            self._get_vfpga_top_file_path(),
            self.test_sim_dump_module,
            self._simulation_time,
            self.disable_input_timing_randomization,
            self._custom_defines,
            stop_event,
        )

        # Wait for the output FIFO to be empty before terminating the Vivado thread,
        # as this thread in turns terminates all IOWriter threads, possibly before
        # all the output has been read.
        def is_fifo_drained() -> bool:
            fd = self._io_writer.output_fd
            if fd is not None:
                buf = array.array('i', [0])
                fcntl.ioctl(fd, termios.FIONREAD, buf)
                return buf[0] == 0

            return True

        while not is_fifo_drained():
            # retry in 1 second
            time.sleep(1.0)
            pass

        if not success:
            output = self.get_simulation_output()
            print(output)
            self._try_to_open_vivado_log_file_on_sim_failure(output)
            raise AssertionError("Failed to run simulation with Vivado.")

    def _convert_data_to_bytearray(
        self, data: Union[Stream, bytearray], stream: int, stream_type: str
    ):
        bytearr = bytearray()
        if isinstance(data, bytearray):
            bytearr = data
        elif isinstance(data, Stream):
            bytearr = data.data_to_bytearray()
        else:
            raise ValueError(
                f"Provided type for {stream_type} stream {stream} had invalid type"
            )
        return bytearr

    @classmethod
    def _ensure_valid_properties(cls):
        # Assertions that ensure we loaded valid properties
        assert N_REGIONS == 1, (
            "FPGA unit-testing only supports a single VFPGA at the moment"
        )
        assert os.path.isdir(UNIT_TEST_FOLDER), (
            f"Could not find unit-test folder at {UNIT_TEST_FOLDER}. Please set the 'UNIT_TEST_DIR' variable in you make script to specify the unit-test directory"
        )
        assert os.path.isdir(VFPGA_SOURCE_FOLDER), (
            f"Could not find source folder for VGPA 0 at {VFPGA_SOURCE_FOLDER}"
        )
        assert os.path.isfile(VIVADO_BINARY_PATH), (
            f"Could not find Vivado at path {VIVADO_BINARY_PATH}. Do you need to rebuilt the sim target?"
        )
        assert os.path.isfile(SRC_V_FPGA_TOP_FILE), (
            f"Unexpected error: Could not find the vfpga_top.svh file at {SRC_V_FPGA_TOP_FILE}"
        )
        assert os.path.isfile(cls._get_vfpga_top_file_path()), (
            f"Unexpected error: Could not find the vfpga_top.svh file at {cls._get_vfpga_top_file_path()}"
        )
        assert os.path.isdir(TEST_BENCH_FOLDER), (
            f"Unexpected error: Could not find test bench directory at {TEST_BENCH_FOLDER}"
        )
        assert FixedSimulationTime.from_string(CLOCK_PERIOD), (
            f"Unexpected error: Clock period {CLOCK_PERIOD} could not be parsed"
        )

    def _setup_logging(self):
        handlers = []

        if self.debug_mode:
            handlers.append(logging.StreamHandler(sys.stdout))

        # Stream handler
        self._log_buffer = StringIO()
        handlers.append(logging.StreamHandler(self._log_buffer))

        # Set the config
        logging.shutdown()
        logging.basicConfig(
            level=logging.DEBUG,
            format="%(asctime)s; %(name)s; %(message)s",
            datefmt="%H:%M:%S",
            handlers=handlers,
            # This overwrites existing configuration
            force=True,
        )

    def _create_io_writer(self) -> SimulationIOWriter:
        """
        Factory method for the SimulationIOWriter class.
        Allows overwriting the generated instances in inheriting classes
        """
        return SimulationIOWriter()

    def _handle_io_error(self) -> None:
        """
        This function is called by the io writer if there is a unexpected
        io error. In this case it is very important to terminate any potentially
        running simulations as they might otherwise run forever.
        """
        if self._simulation_thread is not None and not self._simulation_finished:
            self._simulation_thread.terminate_and_join()

    #
    # Public methods (indented to be called in tests)
    #
    @classmethod
    def setUpClass(cls):
        cls._ensure_valid_properties()

    def setUp(self):
        # Setup logging
        self._setup_logging()

        self._expected_completed_write_transfers = 0
        self._expected_output: List[ExpectedOutput] = []
        self._output_delay_cycles = 0
        # By default we run 4 microseconds
        self._simulation_time: SimulationTime = SimulationTime.fixed_time(
            4, SimulationTimeUnit.MICROSECONDS
        )
        self._simulation_thread = None
        self._simulation_finished = False
        self._io_writer = self._create_io_writer()
        self._io_writer.register_io_error_handler(self._handle_io_error)

        # System verilog defines
        self._custom_defines = {}

        return super().setUp()

    def tearDown(self):
        # Ensure the IO threads are terminated and any error
        # that might have occurred is re-thrown here
        self._io_writer.terminate_io_threads()
        return super().tearDown()

    def get_io_writer(self) -> SimulationIOWriter:
        """
        Returns the IO Writer instance that can be used to directly
        interface with the Simulation/Test bench.

        This IO Writer can be used if the offered convenience methods
        of the FPGATestCase class are not sufficient to model the testing
        scenario.
        """
        return self._io_writer

    def set_system_verilog_defines(self, defines: Dict[str, str]) -> None:
        """
        Provides custom system verilog defines. Each define is a key-value
        pair. Defines can be used to change configuration values in the design
        to adjust it to certain testing conditions.

        E.g. if you have a localparam 'TRANSFER_SIZE_BYTES', you can create a
        define that optionally overwrites its default value like so:

        ```
        `ifdef TRANSFER_SIZE_BYTES_OVERWRITE
            localparam integer TRANSFER_SIZE_BYTES = `TRANSFER_SIZE_BYTES_OVERWRITE;
        `else
            localparam integer TRANSFER_SIZE_BYTES = 4096;
        `endif
        ```

        Defines are set per test case. By default, no define is configured.
        Note that every change in defines causes the project to be re-compiled.
        E.g. if you change a define in every test, every test will require a re-
        compilation of the source code.

        Calling this function multiple times within one test case will overwrite
        the values of previous calls. Any calls should be made before the
        simulation is run.
        """
        self._custom_defines = defines

    def overwrite_simulation_time(self, time: SimulationTime):
        """
        Allows to overwrite the default simulation time of 4us.
        This method needs to be called for every test case that
        wants to overwrite the time.
        """
        assert isinstance(time, SimulationTime)
        self._simulation_time = time

    def write_register(self, config: vFPGARegister):
        """
        Writes the given configuration to a FPGA register.
        """
        self._io_writer.ctrl_write(config)

    def read_register(
        self, id: int, stop_event: threading.Event = None
    ) -> Optional[int]:
        """
        Read a value form a control register with the given id in the simulation.
        Returns the value that has been read.

        Note: This call is blocking until the simulation responds with the value of the register.

        Optionally, a early termination event can be provided. If this is given, the event is checked
        periodically and waiting for the output is canceled when the event is set. In this case,
        None will be returned!
        """
        self._io_writer.ctrl_read(id, stop_event)

    def set_stream_input(
        self,
        stream: int,
        input: Union[Stream, bytearray],
        stream_type=CoyoteStreamType.STREAM_HOST,
    ):
        """
        Stream=0-based

        Each call to this function does the following:
        - Allocates enough memory to fit the given data in the simulation
        - Writes the given data to this memory
        - Invokes a transfer of the memory to the FPGA.

        Calling this function multiple times with the same stream will add input batches to
        the stream that are driven after each other. Each batch will have last set to True.
        If you want to send multiple batches where only the last one is asserted to be last,
        use set_stream_input_batched.

        If the provided input data is a list of boolean, each boolean will be converted to one bit
        with True being 1 and False begin 0. It is asserted that the given list contains only full
        bytes (e.g. the length is a multiple of 8).
        """
        assert stream < MAX_NUMBER_STREAMS
        input_array = self._convert_data_to_bytearray(input, stream, "input")
        vaddr = self._io_writer.allocate_and_write_to_next_free_sim_memory(input_array)
        self._io_writer.invoke_transfer(
            CoyoteOperator.LOCAL_READ,
            stream_type,
            stream,
            vaddr,
            len(input_array),
            True,
        )

    def set_stream_input_batched(
        self,
        stream: int,
        input: Stream,
        n_batches: int,
        stream_type=CoyoteStreamType.STREAM_HOST,
        last_every_batch: bool = False,
    ):
        """
        Stream=0-based

        This method behaves similarly to 'set_stream_input'. However, the input data
        of the given stream is split into n_batches of roughly equal size. Batches are
        driven after each other. The last data beat of each batch will have a keep
        signal according to the number of members.

        E.g. A batch of 20 integers will be driven as a full 512 bit data beat and a
            second data beat with 128 bit valid input.

        The 'last_every_batch' parameter control whether last should be asserted at the
        end of every batch or only after the last batch (default).

        Overall, this method does the following for each batch:

        - Allocates enough memory to fit the given data in the simulation
        - Writes the given data to this memory
        - Invokes a transfer of the memory to the FPGA.
          If last_every_batch is true, this transfer is marked as last. Otherwise, it is
          only marked as last if this is the last batch.
        """
        assert stream < MAX_NUMBER_STREAMS
        assert isinstance(input, Stream), "This function only supports Stream input"
        assert n_batches >= 1, f"Cannot have less than 1 batch. Found {n_batches}."
        batches = input.data_to_batched_bytearray(n_batches)
        for i, batch in enumerate(batches):
            last = i == len(batches) - 1 or last_every_batch
            vaddr = self._io_writer.allocate_and_write_to_next_free_sim_memory(batch)
            self._io_writer.invoke_transfer(
                CoyoteOperator.LOCAL_READ, stream_type, stream, vaddr, len(batch), last
            )

    def remote_rdma_write(self, vaddr: int, input: Stream) -> None:
        """
        Writes the given data to the remote RDMA memory at the given vaddr.
        """
        input_array = self._convert_data_to_bytearray(input, 0, "rdma")
        self._io_writer.remote_rdma_write(vaddr, input_array)

    def local_rdma_read(self, vaddr: int, len: int) -> None:
        """
        Simulates receiving an RDMA read request from the network at the given
        vaddr for the given length.
        """
        self._io_writer.local_rdma_read(vaddr, len)

    def local_rdma_write(self, vaddr: int, input: Stream) -> None:
        """
        Simulates receiving an RDMA write request from the network at the given
        vaddr with the provided data.
        """
        input_array = self._convert_data_to_bytearray(input, 0, "rdma")
        self._io_writer.remote_rdma_write(vaddr, input_array)

    def set_expected_output(
        self,
        stream: int,
        output: Union[Stream, bytearray],
        stream_type=CoyoteStreamType.STREAM_HOST,
        last_transfer=True,
    ) -> None:
        """
        Stream=0-based

        Each call to this function does the following:
            - Allocates enough memory to fit the given data in the simulation
            - Triggers a LOCAL_WRITE to the allocated memory over the size of the given
              output
            - Stores the expected output data and the address of the allocated memory
              When calling 'assert_simulation_output' this will be used to compare
              the actual and expected outputs! If you want more control over the expected
              output, you can set the expected output via the 'set_expected_data_at_memory_location'
              function.

        The stream_type variable lets you control on which stream type the output is expected.

        Moreover, you can control whether the transfer is set to last or not
        """
        assert stream < MAX_NUMBER_STREAMS
        output_array = self._convert_data_to_bytearray(output, stream, "output")
        vaddr = self._io_writer.allocate_next_free_sim_memory(len(output_array))
        self._io_writer.invoke_transfer(
            CoyoteOperator.LOCAL_WRITE,
            stream_type,
            stream,
            vaddr,
            len(output_array),
            last_transfer,
        )
        if last_transfer:
            self._expected_completed_write_transfers += 1

        # Get the stream type if the output is a Stream
        stream_type = None
        if isinstance(output, Stream):
            stream_type = output.stream_type()

        # Set this data to be expected output
        self.set_expected_data_at_memory_location(
            vaddr, output_array, stream_identifier=stream, stream_type=stream_type
        )

    def set_expected_data_at_memory_location(
        self,
        vaddr: int,
        output: bytearray,
        length: int = -1,
        stream_identifier: Union[int, str] = None,
        stream_type: StreamType = None,
    ) -> None:
        """
        Sets the expected contents of the memory location, starting at vaddr to the given
        bytearray.

        This information is used in the 'assert_simulation_output' function to validate
        that the simulation produced the expected output.

        Optionally, a length can be specified. If specified, this length is used to read the
        memory instead of the length of the given bytearray. This is useful in situations
        where more data might have been written to the memory than expected (e.g. when
        the transfer is initiated by the FPGA, not the host).

        It is asserted, that the given memory at vaddr was allocated to at least
        the specified length (either of output or the length parameter).

        Optionally, a stream identifier can be specified. This does not serve any purpose but to make
        debugging easier as assertion errors will have a associated coyote stream in addition
        to the vaddr. The identifier can either be a integer or a string or your choosing.

        Additionally, one can optionally supply a stream_type. Should the output of the design
        not match what is expected, diff files will be generated in the UNIT_TEST folder. By default,
        these files are on a byte level. By supplying the stream_type, the actual and expected output
        can be interpreted using a specific data type. The generated output files will then be based
        on this data type instead of raw bytes, which can ease debugging the issue.
        """
        self._expected_output.append(
            ExpectedOutput(vaddr, output, length, stream_identifier, stream_type)
        )

    def simulate_fpga_non_blocking(self) -> threading.Event:
        """
        Starts the simulation of the FPGA in a non blocking fashion.
        Returns a Event that is raised when the simulation finishes!

        Please ensure to call 'finish_fpga_simulation' once the
        simulation ran to the end to ensure everything is handled properly!
        """
        assert self._simulation_thread is None, (
            "Cannot call 'simulate_fpga_non_blocking twice!"
        )
        # Enable verbose logging if requested
        if self.verbose_logging:
            self._custom_defines["EN_VERBOSE"] = "1"

        self._simulation_thread = SafeThread(self._run_simulation)
        self._simulation_thread.start()
        return self._simulation_thread.get_finished_event()

    def finish_fpga_simulation(self) -> None:
        """
        Ensures proper termination and cleanup of the FPGA simulation.
        Needs to be called after simulate_fpga_non_blocking
        """
        assert self._simulation_thread is not None, (
            "Cannot finish simulation that was never started"
        )
        self._simulation_thread.join_blocking()
        self._simulation_finished = True

    def simulate_fpga(self):
        """
        Blocking call that does the following:

        - Starts a FPGA simulation
        - Waits for all LOCAL_WRITES to complete that have been triggered via the 'set_expected_output' calls.
          If no output has been specified, no local transfer checks will be performed.
        - Asserts all input to be done
        - Waits for the simulation to terminate itself.

        If you need more control over how the simulation is run, you can use the simulate_fpga_non_blocking
        and finish_fpga_simulation calls, which run the simulation in a separate thread and dont perform
        any io calls. However, please make sure to mark the input as done as soon as no more io calls will
        be performed. Otherwise, the simulation will hang!
        """
        # Start the simulation
        end_event = self.simulate_fpga_non_blocking()

        if self._expected_completed_write_transfers > 0:
            # Wait till all the transfers we triggered are completed.
            # This is a blocking call that will be aborted when the end_event should be triggered
            # before it completes (e.g. if the simulation fails to compile)
            self._io_writer.block_till_completed(
                CoyoteOperator.LOCAL_WRITE,
                self._expected_completed_write_transfers,
                end_event,
            )

        # Set all input to be done
        self._io_writer.all_input_done()

        # Wait for the simulation to terminate!
        self.finish_fpga_simulation()

    def get_simulation_output(self) -> str:
        return self._log_buffer.getvalue()

    def write_simulation_output_to_file(self) -> None:
        """
        Writes the output of the simulation to the SIM_OUT_FILE.
        This is useful if the simulation created a lot of output
        that cannot be printed (e.g. in the VSCode test window)
        completely.
        """
        with open(SIM_OUT_FILE, "w+") as f:
            f.write(self._log_buffer.getvalue())

    def assert_simulation_output(self) -> None:
        """
        Checks that all the output provided via the 'set_expected_output' and 'set_expected_data_at_memory_location'
        functions matches the actually received data.
        Will throw a AssertionError with all mismatches if this is not the case.

        Additionally, diff files will be created in the UNIT_TEST folder to ease investigating the issue.
        """
        assert self._simulation_finished, (
            "Cannot assert output when simulation did not finish"
        )

        assert_errors = []

        comparator = OutputComparator(self._testMethodName)
        comparator.clean_previous_diffs()
        for expected_out in self._expected_output:
            try:
                # Read the memory out of the simulation
                actual_out = self._io_writer.read_from_sim_memory(
                    expected_out.get_vaddr(), expected_out.get_length()
                )
                # Compare the output!
                comparator.bitwise_compare_outputs(
                    expected_out.get_expected_output_data(),
                    actual_out,
                    expected_out.get_vaddr(),
                    expected_out.get_stream(),
                    expected_out.get_stream_type()
                )
            except AssertionError as err:
                stream = expected_out.get_stream()
                error = f"Vaddr: {expected_out.get_vaddr()}{f'; Stream {stream}' if stream is not None else ''} : {err}"
                assert_errors.append(AssertionError(error))

        if len(assert_errors) > 0:
            raise ExceptionGroup(
                "\nAt least one simulation output was not as expected."
                + "\n Simulation output:\n"
                + self.get_simulation_output()
                + "\nAssertion errors: ",
                assert_errors,
            )
