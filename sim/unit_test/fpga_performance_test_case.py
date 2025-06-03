
import math
import re

from .utils.exception_group import ExceptionGroup
from .constants import MAX_NUMBER_STREAMS
from .fpga_test_case import FPGATestCase

# TODO: implement!!
class FPGAPerformanceTestCase(FPGATestCase):
    # We can only get accurate performance data if we disable input randomization!
    _disable_input_timing_randomization = True

    # Method that determines the performance from the simulation output
    def _determine_simulation_performance(self):
        send_messages = [[] for _ in range(0, MAX_NUMBER_STREAMS)]
        recv_messages = [[] for _ in range(0, MAX_NUMBER_STREAMS)]

        # Go through the sim output line by line and read out the timings
        # of the send & receive messages
        for line in self.get_simulation_output().splitlines():
            # Example: 136000: AXIS [0] send() completed ...
            send_match = re.match(r"$[0-9]+: AXIS \[([0-9])\] send() completed", line)
            if send_match:
                # Group 2 identifies the stream, Group 1 identifies the time
                send_messages[int(send_match.group(2))].append(int(send_match.group(1)))
            # Example: 808000: AXIS [0] recv() completed
            recv_match = re.match(r"$[0-9]+: AXIS \[([0-9])\] recv() completed", line)
            if recv_match:
                # Group 2 identifies the stream, Group 1 identifies the time
                recv_messages[int(recv_match.group(2))].append(int(recv_match.group(1)))

        print("Found performance!")
        print(send_messages)
        print(recv_messages)    

        # print("\t\t\t\t\tSIMULATION PERFORMANCE")
        # # Calculate cycles for each stream that had an input!
        # for index, data in enumerate(self._inputs):
        #     if len(data) == 0:
        #         continue

        #     n_bytes = sum([len(batch) for batch in data ])
        #     n_data_beats = math.ceil(n_bytes / 64)
        #     # We need to add 1
        #     # E.g. if the driver started in cycle 1 and finished in cycle 4, it took 4 cycles!
        #     n_driver_cycles = driver_finished[index] - driver_started[index] + 1
        #     # We need to subtract 1
        #     # E.g. if we get output in the 50th cycle, we waited 49 cycle
        #     n_cycles_latency = monitor_started[index] - driver_started[index] - 1
        #     # Add one for the same reason as above
        #     n_cycles_monitor = monitor_finished[index] - monitor_started[index] + 1
        #     avg_cycles = n_cycles_monitor / n_data_beats
        #     # We add the cycles if the driver could not drive one input per cycle!
        #     n_cycles_with_driver_delay = n_cycles_monitor + (n_driver_cycles - n_data_beats)
        #     avg_cycles_with_driver = n_cycles_with_driver_delay / n_data_beats
        #     # Update internal storage of performance for comparison!
        #     self._avg_cycles_with_driver[index] = avg_cycles_with_driver
        #     print(f"Stream [{index}]\t{n_bytes} bytes\t" + \
        #         f"{n_data_beats} data beats\t" + \
        #         f"{n_driver_cycles} cycle driver\t" + \
        #         f"{n_cycles_monitor} cycle monitor\t" + \
        #         f"{avg_cycles:.2f} avg cycle per batch\t" + \
        #         f"{avg_cycles_with_driver:.2f} avg cycle per batch with driver\t" + \
        #         f"{n_cycles_latency} cycle latency"
        #     )

        print()

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
        assert (stream < MAX_NUMBER_STREAMS)
        self._expected_performance[stream] = cycles

    def set_expected_avg_cycles_per_batch_for_all_streams(self, cycles: float):
        for i in range(0, MAX_NUMBER_STREAMS):
            self.set_expected_avg_cycles_per_batch(i, cycles)

    def assert_expected_performance(self):
        assert_errors = []

        for index in range(0, MAX_NUMBER_STREAMS):
            if self._expected_performance[index] is not None and self._avg_cycles_with_driver[index] is not None:
                if self._avg_cycles_with_driver[index] > self._expected_performance[index]:
                    assert_errors.append(
                        AssertionError(f"Expected performance stream {index}: " + \
                                       f"{self._expected_performance[index]}. Actual performance: " + \
                                       f"{self._avg_cycles_with_driver[index]}")
                    )

        if len(assert_errors) > 0:
            raise ExceptionGroup("\nAt least one performance target was not met:\n", assert_errors)