import math
import re
import logging
import threading
from typing import List, Tuple

from .utils.exception_group import ExceptionGroup
from .constants import MAX_NUMBER_STREAMS, CLOCK_PERIOD
from .fpga_test_case import FPGATestCase
from .io_writer import SimulationIOWriter, CoyoteOperator, CoyoteStreamType
from .simulation_time import FixedSimulationTime, SimulationTimeUnit


class PerformanceSimulationIOWriter(SimulationIOWriter):
    def __init__(self):
        super().__init__()
        self.input_bytes = [0 for _ in range(0, MAX_NUMBER_STREAMS)]

    def get_input_bytes(self) -> List[int]:
        """
        Returns the number of input bytes for each stream.
        The number defaults to 0 if no input was send on this stream.
        """
        return self.input_bytes

    # Overwrite of the super class that captures how many bytes
    # have been transferred into the design
    def invoke_transfer(
        self,
        op_code: CoyoteOperator,
        stream_type: CoyoteStreamType,
        dest_coyote_stream: int,
        vaddr: int,
        len: int,
        last: bool,
    ) -> None:
        super().invoke_transfer(
            op_code, stream_type, dest_coyote_stream, vaddr, len, last
        )

        if (
            op_code == CoyoteOperator.LOCAL_READ
            or op_code == CoyoteOperator.LOCAL_TRANSFER
        ):
            self.input_bytes[dest_coyote_stream] += len


class FPGAPerformanceTestCase(FPGATestCase):
    # We can only get accurate performance data if we disable input randomization!
    _disable_input_timing_randomization = True
    # We need verbose logs to print the logs we parse below
    _verbose_logging = True

    def __init__(self, methodName="runTest"):
        super().__init__(methodName)
        # Convert the clock period to picoseconds!
        clock_period = FixedSimulationTime.from_string(CLOCK_PERIOD)
        self._clock_period_ps = clock_period.convert_to_unit(
            SimulationTimeUnit.PICOSECONDS
        )

    def _create_io_writer(self) -> SimulationIOWriter:
        """
        Overwrite the SimulationIOWriter factors method
        to inject a IO writer that captures the number of
        input bytes transferred
        """
        return PerformanceSimulationIOWriter()

    def _convert_execution_time_to_cycle(self, time: int) -> int:
        """
        Given a timestamp in picoseconds, returns the number of cycles
        the design ran at the given timestamp. This includes the cycle
        started at the given timestamp.
        """
        assert time % self._clock_period_ps == 0, (
            "Found timestamp {time} of send/recv operation in simulation logs that"
            + f"did not align with the clock time of {self._clock_period_ps}ps"
        )
        return time // self._clock_period_ps

    def _parse_send_recv_cycles(self) -> Tuple[List[int], List[int]]:
        """
        Parses the cycles in which output was received or send from
        the simulation output log
        """

        def append_match_to_list(list: List[List[int]], match):
            timestamp = int(match.group(1))
            stream = int(match.group(2))
            cycles = self._convert_execution_time_to_cycle(timestamp)
            list[stream].append(cycles)

        send_messages = [[] for _ in range(0, MAX_NUMBER_STREAMS)]
        recv_messages = [[] for _ in range(0, MAX_NUMBER_STREAMS)]

        # Go through the sim output line by line and read out the timings
        # of the send & receive messages
        for line in self.get_simulation_output().splitlines():
            # Example: 136000: AXIS [0] send() completed ...
            send_match = re.search(
                r"([0-9]+): \[DEBUG\] \w+.svh\:\d+\: \[([0-9])\] send\(\) completed.", line
            )
            if send_match:
                append_match_to_list(send_messages, send_match)
            # Example: 808000: AXIS [0] recv() completed
            recv_match = re.search(
                r"([0-9]+): \[DEBUG\] \w+.svh\:\d+\: \[([0-9])\] recv\(\) completed.", line
            )
            if recv_match:
                append_match_to_list(recv_messages, recv_match)

        return (send_messages, recv_messages)

    # Method that determines the performance from the simulation output
    def _determine_simulation_performance(self):
        """
        Calculates the performance in cycles for all streams that had data
        """
        logger = logging.getLogger("FPGAPerformanceTest")

        def log(message):
            logger.info(message)
            # If we are not in debug mode we still
            # print a performance overview for visibility
            if not self._debug_mode:
                print(message)

        log("SIMULATION PERFORMANCE")

        io_writer: PerformanceSimulationIOWriter = self.get_io_writer()
        input_bytes = io_writer.get_input_bytes()

        (send_cycles, recv_cycles) = self._parse_send_recv_cycles()

        # Calculate cycles for each stream that had an input!
        for stream, n_bytes in enumerate(input_bytes):
            # If there was not output on this stream, continue
            if n_bytes == 0:
                continue

            # If there is no data for both send & recv, continue
            if len(send_cycles[stream]) == 0 or len(recv_cycles[stream]) == 0:
                continue

            n_data_beats = math.ceil(n_bytes / 64)

            # + 1 because if the driver started in cycle 1 and finished in cycle 4, it took 4 cycles!
            n_cycles_send = send_cycles[stream][-1] - send_cycles[stream][0] + 1
            # -1 because if we get output in the 50th cycle, we waited 49 cycle
            n_cycles_latency = recv_cycles[stream][0] - send_cycles[stream][0] - 1
            # Add one for the same reason as above
            n_cycles_recv = recv_cycles[stream][-1] - recv_cycles[stream][0] + 1
            avg_cycles_per_batch = n_cycles_recv / n_data_beats
            # We add the cycles if the driver could not drive one input per cycle!
            n_cycles_with_driver_delay = n_cycles_recv + (n_cycles_send - n_data_beats)
            avg_cycles_per_batch_with_driver = n_cycles_with_driver_delay / n_data_beats
            # Update internal storage for the assertions
            self._avg_cycles_with_driver[stream] = avg_cycles_per_batch_with_driver
            log(
                f"Stream [{stream}]\t{n_bytes} bytes\t"
                + f"{n_data_beats} data beats\t"
                + f"{n_cycles_send} cycle send\t"
                + f"{n_cycles_recv} cycle recv\t"
                + f"{avg_cycles_per_batch:.2f} avg cycle per batch\t"
                + f"{avg_cycles_per_batch_with_driver:.2f} avg cycle per batch with sending delay\t"
                + f"{n_cycles_latency} cycle latency"
            )

    #
    # Public methods (indented to be called in tests)
    #
    def setUp(self):
        super().setUp()
        self._expected_performance = [None] * MAX_NUMBER_STREAMS
        self._avg_cycles_with_driver = [None] * MAX_NUMBER_STREAMS

    # Overwrite finish simulation method
    def finish_fpga_simulation(self):
        super().finish_fpga_simulation()
        self._determine_simulation_performance()

    def set_expected_avg_cycles_per_batch(self, stream: int, cycles: float):
        """
        Stream=0-based
        """
        assert stream < MAX_NUMBER_STREAMS
        self._expected_performance[stream] = cycles

    def set_expected_avg_cycles_per_batch_for_all_streams(self, cycles: float):
        """
        Convenience function that calls 'set_expected_avg_cycles_per_batch'
        for all streams with the same value.
        """
        for i in range(0, MAX_NUMBER_STREAMS):
            self.set_expected_avg_cycles_per_batch(i, cycles)

    def assert_expected_performance(self):
        """
        Asserts the the actual, calculated performance matches the expectations
        """
        assert_errors = []

        for index in range(0, MAX_NUMBER_STREAMS):
            if (
                self._expected_performance[index] is not None
                and self._avg_cycles_with_driver[index] is not None
            ):
                if (
                    self._avg_cycles_with_driver[index]
                    > self._expected_performance[index]
                ):
                    assert_errors.append(
                        AssertionError(
                            f"Expected performance stream {index}: "
                            + f"{self._expected_performance[index]}. Actual performance: "
                            + f"{self._avg_cycles_with_driver[index]}"
                        )
                    )

        if len(assert_errors) > 0:
            raise ExceptionGroup(
                "\nAt least one performance target was not met:\n", assert_errors
            )
