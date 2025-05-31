import os

import unittest

from typing import Union, List
import threading

from .process_runner import ProcessRunner, VivadoRunner
from .simulation_time import SimulationTime, SimulationTimeUnit
from .fpga_stream import Stream
from .constants import UNIT_TEST_FOLDER, MAX_NUMBER_STREAMS
from .fpga_configuration import FPGAConfiguration
from .io_writer import SimulationIOWriter, CoyoteOperator, CoyoteStreamType
from .utils.bool import bools_to_bytearray
from .utils.exception_group import ExceptionGroup
from .utils.thread_handler import SafeThread
from .output_comparison import OutputComparator

SIM_OUT_FILE = os.path.join(UNIT_TEST_FOLDER, "sim.out")


class ExpectedOutput:
    """
    Small wrapper class to describe expected output at specific
    memory locations
    """

    def __init__(self, vaddr: int, output: bytearray, stream=None):
        self.vaddr = vaddr
        self.output = output
        self.stream = stream

    def get_vaddr(self) -> int:
        return self.vaddr

    def get_expected_output_data(self) -> bytearray:
        return self.output

    def get_stream(self) -> int:
        return self.stream


class FPGATestCase(unittest.TestCase):
    """
    Base class with shared functionality for all FPGA-based tests.
    Unfortunately, there are sources shared between the tests. Therefore,
    tests have to be run one at a time.
    """

    # TODO: Implement!
    _alternative_vfpga_top_file = None
    # Whether to disable input randomization (good for correctness)
    # In favor of getting exact performance measurements (latency & cycles)
    # TODO: Implement!
    _disable_input_timing_randomization = False
    # A specific module to filter the sim vcd dump by.
    # Without specifying this value, the dump will contain all signals in tb_user.
    # With this value, the signals can be further restricted.
    # E.g. if your vpga_top.svh contains a module instantiation called 'db_pipeline',
    # which contains a module called 'inst_filter', the filter could be like this:
    # db_pipeline/inst_filter
    # TODO: Check, is this implemented?
    _test_sim_dump_module = ""

    def __init__(self, methodName="runTest"):
        super().__init__(methodName)

    #
    # Private methods
    #
    def is_list_of_booleans(self, param):
        return isinstance(param, list) and all(isinstance(elem, bool) for elem in param)

    def _is_running_inside_vscode(self):
        return "VSCODE_CWD" in os.environ

    def _try_to_open_vivado_log_file_on_sim_failure(self, output_lines):
        if not self._is_running_inside_vscode():
            return

        log_files = ["xvlog.log", "elaborate.log", "xvhdl.log"]

        for line in output_lines:
            for log_file in log_files:
                if log_file in line:
                    # Split the string, find the path to the log_file with the format (e.g. for xvlog): '{PATH}/xvlog.log'
                    path_line = list(
                        filter(lambda part: part.endswith(log_file), line.split("'"))
                    )
                    for line in path_line:
                        if os.path.exists(line):
                            print(
                                f"NOTE: Opening error file {log_file} for you in current VSCode window"
                            )
                            ProcessRunner().try_open_file_in_vscode(line)

    def _run_simulation(self, stop_event: threading.Event):
        """
        Private method that runs the simulation
        Is called in a thread to ensure the simulation can run non-blocking
        """
        # Note: The stop_event is ignored since simulation always needs to run to the end
        print("RUNNING SIMULATION")
        compilation_id = self._alternative_vfpga_top_file
        (success, lines) = VivadoRunner(print_logs=self._debug_mode).run_simulation(
            compilation_id, self._test_sim_dump_module, self._simulation_time
        )
        self._sim_out = "\n".join(lines)
        if not success:
            print(self._sim_out)
            self._try_to_open_vivado_log_file_on_sim_failure(lines)
            raise AssertionError("Failed to run simulation with Vivado.")

    def _convert_data_to_bytearray(
        self, data: Union[Stream, bytearray, List[bool]], stream, stream_type
    ):
        bytearr = bytearray()
        if self.is_list_of_booleans(data):
            bytearr = bools_to_bytearray(data)
        elif isinstance(data, bytearray):
            bytearr = data
        elif isinstance(data, Stream):
            bytearr = data.data_to_bytearray()
        else:
            raise ValueError(
                f"Provided type for {stream_type} stream {stream} had invalid type"
            )
        return bytearr

    # TODO: Implement
    # @classmethod
    # def _write_randomization_mode(cls):
    #     with open(RANDOMIZATION_FILE, "wb+") as f:
    #         if cls._disable_input_timing_randomization == True:
    #             f.write(bytearray([0]))
    #         else:
    #             f.write(bytearray([255]))

    # TODO: Implement
    # Overwrite vfpga_top.sv in sim folder
    # @classmethod
    # def _create_tb_design_logic_for_test(cls):
    #     if cls._test_configuration_file == "" or not os.path.isfile(cls._test_configuration_file):
    #         raise ValueError(
    #             "Cannot create unit-test with empty/invalid test-configuration file. Please overwrite the '_test_configuration_file' class property")

    #     if cls._general_configuration_file == "" or not os.path.isfile(cls._general_configuration_file):
    #         raise ValueError(
    #             "Cannot create unit-test with empty/invalid general-configuration file")

    #     output_buffer = ""
    #     with open(cls._general_configuration_file, "r") as config:
    #         for line in config:
    #             if line.strip() == USER_LOGIC_REPLACEMENT_STRING:
    #                 with open(cls._test_configuration_file) as test_config:
    #                     output_buffer += test_config.read()
    #             else:
    #                 output_buffer += line

    # with open(USER_LOGIC_TARGET_FILE, "w") as output:
    #    output.write(output_buffer)

    # TODO: Move to my class
    # @classmethod
    # def _ensure_hw_was_build(cls):
    #     if not os.path.exists(HW_BUILD_FOLDER):
    #         print("Running simulation setup")
    #         ProcessRunner().run_bash_script("sim_setup.sh")
    #     else:
    #         print("build_hw exists, skipping creation")

    # TODO: Add method to expose IO_writer directly for more complex setups

    #
    # Public methods (indented to be called in tests)
    #
    @classmethod
    def setUpClass(cls):
        pass
        # cls._create_tb_design_logic_for_test()
        # cls._ensure_hw_was_build()
        # cls._write_randomization_mode()

    def setUp(self):
        self._expected_completed_write_transfers = 0
        self._expected_output: List[ExpectedOutput] = []
        self._output_delay_cycles = 0
        # By default we run 4 microseconds
        self._simulation_time: SimulationTime = SimulationTime.fixed_time(
            4, SimulationTimeUnit.MICROSECONDS
        )
        self._simulation_thread = None
        self._sim_out = ""
        self._simulation_finished = False
        self._io_writer = SimulationIOWriter()
        # Whether the test case should be run in 'debug' mode -> This means all logs will
        # be printed immediately. This allows one to monitor the behavior of vivado
        # and the io_writer
        self._debug_mode = False
        return super().setUp()

    def enable_debug_mode(self):
        """
        Whether to enable the debug mode for the test case.
        In debug mode, the following is done:
        - all log output is printed immediately

        This allows one to debug the test behavior
        """
        self._debug_mode = True
        self._io_writer.enable_debug_mode()

    def overwrite_simulation_time(self, time: SimulationTime):
        """
        Allows to overwrite the default simulation time of 4us.
        This method needs to be called for every test case that
        wants to overwrite the time
        """
        assert isinstance(time, SimulationTime)
        self._simulation_time = time

    def write_register(self, config: FPGAConfiguration):
        """
        Writes the given configuration to a FPGA register
        """
        self._io_writer.ctrl_write(config)

    def set_stream_input(
        self,
        stream: int,
        input: Union[Stream, bytearray, List[bool]],
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
        for batch, i in enumerate(batches):
            last = i == len(batches) - 1 or last_every_batch
            vaddr = self._io_writer.allocate_and_write_to_next_free_sim_memory(batch)
            self._io_writer.invoke_transfer(
                CoyoteOperator.LOCAL_READ, stream_type, stream, vaddr, len(batch), last
            )

    def set_expected_output(
        self,
        stream: int,
        output: Union[Stream, bytearray, List[bool]],
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

        # Set this data to be expected output
        self.set_expected_data_at_memory_location(vaddr, output_array, stream)

    def set_expected_data_at_memory_location(
        self, vaddr: int, output: bytearray, stream: int = None
    ) -> None:
        """
        Sets the expected contents of the memory location, starting at vaddr to the given
        bytearray.

        This information is used in the 'assert_simulation_output' function to validate
        that the simulation produced the expected output.

        It is asserted, that the given memory at vaddr was allocated to at least
        the length of the given bytearray.

        Optionally, a stream can be specified. This does not serve any purpose but to make
        debugging easier as assertion errors will have a associated coyote stream in addition
        to the vaddr.
        """
        self._expected_output.append(ExpectedOutput(vaddr, output, stream))

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
        self._simulation_thread.join()
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

    # def set_read_output_cycles_delay(self, delay_in_cycles: int):
    #     """
    #     Specifies a number of cycles by which reading the stream output gets
    #     delayed. This can be used to test proper back pressuring
    #     """
    #     self._output_delay_cycles = delay_in_cycles

    def get_simulation_output(self) -> str:
        assert self._simulation_finished, (
            "Cannot return output of unfinished simulation. Enable debug mode if you want to monitor the simulation"
        )
        return self._sim_out

    def write_simulation_output_to_file(self) -> None:
        """
        Writes the output of the simulation to the SIM_OUT_FILE.
        THis is useful if the simulation created a lot of output
        that cannot be printed (e.g. in the VSCode test window)
        completely.
        """
        assert self._simulation_finished, (
            "Cannot write output of unfinished simulation. Enable debug mode if you want to monitor the simulation"
        )
        with open(SIM_OUT_FILE, "w+") as f:
            f.write(self._sim_out)

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
                    expected_out.get_vaddr(),
                    len(expected_out.get_expected_output_data()),
                )
                # Compare the output!
                comparator.bitwise_compare_outputs(
                    expected_out.get_expected_output_data(),
                    actual_out,
                    expected_out.get_vaddr(),
                    expected_out.get_stream(),
                )
            except AssertionError as err:
                stream = expected_out.get_stream()
                prefix = f"Vaddr: {expected_out.get_vaddr()} {f'; Stream {stream}' if stream is not None else ''} :"
                assert_errors.append(prefix + err)

        if len(assert_errors) > 0:
            raise ExceptionGroup(
                "\nAt least one simulation output was not as expected."
                + "\nVivado output:\n"
                + self._sim_out
                + "\nAssertion errors: ",
                assert_errors,
            )
