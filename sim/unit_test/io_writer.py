import struct
import bisect
import time
import threading
import select
from collections.abc import Callable
from queue import Queue, Empty
from typing import Optional, List, Union, Dict, BinaryIO
from enum import Enum
from pathlib import Path
from io import StringIO
import os
import logging
import inspect

from .constants import (
    BYTE_ORDER,
    MAX_NUMBER_STREAMS,
    IO_INPUT_FILE_NAME,
    IO_OUTPUT_FILE_NAME,
)
from .fpga_configuration import FPGAConfiguration
from .utils.thread_handler import SafeThread


class SocketSendMessageType(Enum):
    CONTROL = 0
    GET_MEMORY = 1
    WRITE_MEMORY = 2
    INVOKE = 3
    SLEEP = 4
    CHECK_COMPLETION = 5


class SocketReceiveMessageType(Enum):
    GET_CSR = 0
    HOST_WRITE = 1
    IRQ = 2
    CHECK_COMPLETED = 3


class CoyoteOperator(Enum):
    # Transfer data from the simulation memory to the design.
    # The stream on which the data will be send can be decided via the CoyoteStream parameter.
    LOCAL_READ = 1
    # Transfer data from one of the data streams (card, host, RDMA) to the simulation memory.
    # The stream from which the data will be received can be decided via the CoyoteStream parameter.
    LOCAL_WRITE = 2
    # LOCAL_READ and LOCAL_WRITE in parallel
    LOCAL_TRANSFER = 3
    # Note: Other operators are not yet supported by the test bench


class CoyoteStreamType(Enum):
    # Stream data from/to FPGA memory
    STREAM_CARD = 0
    # Stream data from/to CPU host streams
    STREAM_HOST = 1
    # Stream data via RDMA
    STREAM_RDMA = 2
    # Note: Stream_TCP is not supported by the test bench


class SimulationIOWriter:
    """
    Handles the communication between the python unit-tests and the test bench running in the simulation
    by writing/reading to/from a unix named pipe.
    """

    def __init__(self):
        # See https://docs.python.org/3/library/struct.html
        self.byte_order = "<" if BYTE_ORDER == "little" else ">"

        self.logger = logging.getLogger("IOWriter")

        # Function to all when we receive an interrupt
        self.interrupt_handler = None

        # Sorted list of vaddresses of simulation/host memory allocations
        # performed via the 'allocate_sim_memory' call.
        # This is used to:
        # - Perform bound checks on any method that writes/reads memory
        # - Store the actual data such that it can be written/read
        # Note: We use a RLock here that allows us to acquire a lock
        # multiple times with the same lock to ease the implementation
        # via different methods!
        self.allocation_lock = threading.RLock()
        self.allocation_addresses = []
        # List of the actual memory.
        # Maps a vaddress to a bytearray that contains the data
        self.allocations: Dict[int, bytearray] = {}

        # Note: the queue implementation is already thread safe!
        self.input_queue = Queue()
        self.input_done_event = threading.Event()
        # Start the thread to produce the input file
        self.input_thread = SafeThread(self._write_simulation_input_entry)
        self.input_thread.start()

        # This queue is used to send the output of getCSR to a consumer
        self.csr_output_queue = Queue()
        self.check_completed_output_queue = Queue()
        # Start the thread to read the output file
        self.output_thread = SafeThread(self._read_simulation_output_entry)
        self.output_thread.start()

    def __del__(self):
        # Request termination from the background threads
        # (in case they did not already terminate)
        # Note: This will re-raise any exceptions that might have
        # occurred during thread execution
        # TODO: Listen to finish event to join threads early
        # -> Cancel test execution early should one of them fail
        self.input_thread.join()
        self.output_thread.join()

    #
    # Private methods
    #
    def _create_named_pipe(self, pipe_path: str):
        if Path(pipe_path).exists():
            os.remove(pipe_path)
        os.mkfifo(pipe_path)

    def _open_pipe_none_blocking(
        self, pipe_path: str, termination_event: threading.Event, mode: int
    ) -> Optional[int]:
        """
        Opening a named pipe in unix blocks until it was opened by both sides.
        Given that starting a simulation can fail in various ways (e.g. compilation error),
        we need to try to open the file in a non-blocking manner that allows us to properly
        terminate the thread, should it be impossible to open the pipe.

        pipe_path           : string path to the named pipe to open
        termination_event   : When set, we will stop trying to open the pipe
        mode                : The file mode to open the file.

        Returns a file descriptor if opening the pipe was successful and None otherwise.
        """
        while not termination_event.is_set():
            try:
                # Open in non-blocking mode
                return os.open(pipe_path, mode | os.O_NONBLOCK)
            except OSError:
                # Retry in 1 second
                time.sleep(1.0)

        return None

    def _poll_till_data_can_be_read(
        self, fd: int, termination_event: threading.Event
    ) -> bool:
        """
        Uses the poll system call to poll the given file descriptor
        until data can be read from the file or the termination event
        was set.

        Returns whether data is available to be read (True) or
        the termination event was triggered first (False)
        """
        poller = select.poll()
        poller.register(fd, select.POLLIN)

        while not termination_event.is_set():
            # Poll with 1 second timeout
            events = poller.poll(1000)

            for _, event in events:
                if event & select.POLLIN:
                    return True

        return False

    def _read_get_csr_output(self, output_file: BinaryIO, logger: logging.Logger):
        # The output should be a single, 8 byte value
        format = f"{self.byte_order}q"
        size = struct.calcsize(format)
        data = output_file.read(size)
        [csr_value] = struct.unpack(format, data)
        # We set the result in the csr_output_queue
        # -> The consumer thread can wait for data on the queue
        logger.info(f"Got CSR value {csr_value}")
        self.csr_output_queue.put(csr_value)

    def _read_host_write_output(self, output_file: BinaryIO, logger: logging.Logger):
        # First: Read the header.
        # Consisting of two longs for the vaddr and output length
        format = f"{self.byte_order}qq"
        size = struct.calcsize(format)
        data = output_file.read(size)
        (vaddr, length) = struct.unpack(format, data)

        # Note keep the lock throughout all calls to ensure the data does not
        # change between checking the start address and update the data
        with self.allocation_lock:
            # Check that this memory has been allocated

            start_address = self._get_containing_allocation(vaddr, length)
            assert start_address is not None, (
                f"Simulation tried to write {length} bytes to vaddr {vaddr}, which was not allocated!"
                + self._get_allocated_memory_properties()
            )

            # Read the actual data
            output_data = output_file.read(length)

            # Update the local memory to the data we got!
            relative_index = vaddr - start_address
            self.allocations[start_address][
                relative_index : relative_index + length
            ] = output_data

            logger.info(
                f"Received {length} bytes starting from vaddr {vaddr} from FPGA"
            )

    def _read_interrupt_output(self, output_file: BinaryIO, logger: logging.Logger):
        # The output is one byte for the pid and 4 bytes for the value
        format = f"{self.byte_order}ci"
        size = struct.calcsize(format)
        data = output_file.read(size)
        (pid, value) = struct.unpack(format, data)

        logger.info(f"Got interrupt for pid {pid} with value {value}")

        if self.interrupt_handler is not None:
            # TODO: Handle errors thrown in handler
            # Call the interrupt handler.
            # Note: We call out of the context of the output handler.
            # This means it is not a an issue for the handler to do
            # calls to the IOWriter (e.g. acquire more memory)
            # Since the output handler should not be holding any
            # of the IOWriter's locks
            self.interrupt_handler(pid, value)

    def _read_check_completed_output(
        self, output_file: BinaryIO, logger: logging.Logger
    ):
        format = f"{self.byte_order}q"
        size = struct.calcsize(format)
        data = output_file.read(size)
        [count] = struct.unpack(format, data)
        logger.info(f"Got check completed count {count}")
        # Put it into the queue for waiting threads!
        self.check_completed_output_queue.put(count)

    def _read_simulation_output(
        self, output_file: BinaryIO, stop_event: threading.Event, logger: logging.Logger
    ):
        # While we still get output!
        while not stop_event.is_set():
            # Read the first byte, which identifies the message type
            byte = output_file.read(1)

            if not byte:
                # For some reason, it can be that we get a pre-mature EOF
                # Although the simulation is still writing content.
                # We solve this problem now by running until we get the stop
                # event and delaying the next read for some time if we get a EOF
                time.sleep(1.0)
                continue

            # Determine the message type
            # Note: This will raise an exception if the type is unknown!
            message_type = SocketReceiveMessageType(int.from_bytes(byte, BYTE_ORDER))
            logger.info(f"Got Output message {message_type.name} from FPGA")
            # Handle according to the message type
            match message_type:
                case SocketReceiveMessageType.GET_CSR:
                    self._read_get_csr_output(output_file, logger)
                case SocketReceiveMessageType.HOST_WRITE:
                    self._read_host_write_output(output_file, logger)
                case SocketReceiveMessageType.IRQ:
                    self._read_interrupt_output(output_file, logger)
                case SocketReceiveMessageType.CHECK_COMPLETED:
                    self._read_check_completed_output(output_file, logger)

    def _read_simulation_output_entry(self, stop_event: threading.Event):
        """
        Method running in separate thread to handle simulation output
        """
        # Create the named pipe
        file_path = IO_OUTPUT_FILE_NAME
        self._create_named_pipe(file_path)
        logger = logging.getLogger("IOWriterOutputThread")

        try:
            # First, try to open the pipe!
            fd = self._open_pipe_none_blocking(file_path, stop_event, os.O_RDONLY)

            # Terminate the thread if opening the file failed
            if not fd:
                return

            # In case of the output file, we can open the pipe as a reader immediately.
            # However, the pipe will only return EOF until no writer is connected to is.
            # Connecting a writer can take some time since the simulation needs to be started
            # first. Therefore, we use the poll system call to wait for any input to be
            # available on the pipe before we proceed.
            if not self._poll_till_data_can_be_read(fd, stop_event):
                logger.info("Could not open output file since stop event was received")
                return

            logger.info(f"Successfully opened output file at {file_path}")

            # Do the actual processing
            with os.fdopen(fd, "rb", buffering=0) as output_file:
                self._read_simulation_output(output_file, stop_event, logger)

            logger.info("Closing output file")
        finally:
            # Delete the pipe again!
            os.remove(file_path)

    def _any_event_set(self, *events: List[threading.Event]):
        if events:
            for event in events:
                if event and event.is_set():
                    return True
        return False

    def _try_dequeue_till_stop(self, queue: Queue, *stop_events: List[threading.Event]):
        """
        Tries to dequeue from the given queue till this succeeds or the stop_event is raised.
        If the stop event was raised, None will be returned.
        If no stop_event is given, a blocking dequeue is performed
        """
        if stop_events:
            while not self._any_event_set(*stop_events):
                try:
                    # Try to dequeue next element
                    return queue.get(block=True, timeout=0.1)
                except Empty:
                    pass
                except:
                    raise

            return None

        return queue.get()

    def _write_simulation_input(
        self, input_file: BinaryIO, stop_event: threading.Event, logger: logging.Logger
    ):
        def flush_elem(elem):
            # Note: Writing can block if the buffer is full.
            # Therefore, we need a retry mechanism that can abort
            # when the stop_event is triggered.
            bytes_written = 0
            while bytes_written < len(elem):
                if stop_event.is_set():
                    return
                # Try to write
                try:
                    chunk = elem[bytes_written:]
                    written = input_file.write(chunk)
                    bytes_written += written
                    input_file.flush()
                except BlockingIOError:
                    stop_event.wait(0.1)
                except:
                    print("FAILED TO WRITE SIMULATION INPUT")
                    raise

        while not stop_event.is_set():
            # Check if the input is done and all elements should be flushed and the file closed!
            if self.input_done_event.isSet():
                logger.info("Flushing all remaining input as done event was set")
                # Drain queue and then return
                while not self.input_queue.empty():
                    flush_elem(self.input_queue.get())
                return
            else:
                elem = self._try_dequeue_till_stop(
                    self.input_queue, stop_event, self.input_done_event
                )
                if elem:
                    flush_elem(elem)

    def _write_simulation_input_entry(self, stop_event: threading.Event):
        """
        Method running in separate thread to handle simulation input
        """
        # Create the named pipe
        file_path = IO_INPUT_FILE_NAME
        self._create_named_pipe(file_path)
        logger = logging.getLogger("IOWriterInputThread")

        try:
            # First, try to open the pipe!
            fd = self._open_pipe_none_blocking(file_path, stop_event, os.O_WRONLY)

            # Terminate the thread if opening the file failed
            if not fd:
                return

            logger.info(f"Successfully opened input file at {file_path}")

            # Do the actual processing
            with os.fdopen(fd, "wb") as input_file:
                self._write_simulation_input(input_file, stop_event, logger)

            logger.info("Closing input file")
        finally:
            # Delete the pipe again!
            os.remove(file_path)

    def _get_allocated_memory_properties(self) -> str:
        with self.allocation_lock:
            buffer = StringIO()
            buffer.write("Allocated Memory Dump\n\n")
            for vaddr in self.allocation_addresses:
                buffer.write(
                    f"\tvaddr: {vaddr}, length: {len(self.allocations[vaddr])}"
                )
            buffer.write("\n")

            return buffer.getvalue()

    def _get_containing_or_neighboring_allocation(self, vaddr: int) -> Optional[int]:
        """
        Returns the start address of an existing allocation, if:
         - It contains the given vaddr
         - The given vaddr is the next address after the allocation
        """
        with self.allocation_lock:
            if not self.allocation_addresses:
                return None

            # This give us the position (index) after the first vaddr y in the allocation list for which
            # it holds that vaddr >= y. I.e the index where y would be inserted into the list to maintain
            # the sorted order.
            position = bisect.bisect_right(self.allocation_addresses, vaddr)

            # Check the allocation at position - 1 (if it exists)
            if position > 0:
                start_address = self.allocation_addresses[position - 1]
                size = len(self.allocations[start_address])
                # Check if vaddr is:
                #  - Either within bounds of the existing allocation
                #  - OR: the next address!
                if vaddr <= start_address + size:
                    return start_address

            return None

    def _get_containing_allocation(self, vaddr: int, size: int) -> Optional[int]:
        """
        Returns the vaddr of the allocation that contains the memory of the given vaddr
        and size, if any exists.
        """
        with self.allocation_lock:
            start_address_existing_alloc = (
                self._get_containing_or_neighboring_allocation(vaddr)
            )
            if start_address_existing_alloc is None:
                return None

            allocation_size = len(self.allocations[start_address_existing_alloc])

            # Check whether the vaddr and size are within bounds!
            if (start_address_existing_alloc + allocation_size - 1) >= (
                vaddr + size - 1
            ):
                return start_address_existing_alloc

            return None

    def _add_memory_allocation(self, vaddr: int, size: int):
        """
        Adds a new allocation of the given size to the internal tracking
        """
        with self.allocation_lock:
            # First, check if there is an existing allocation that contains the vaddr, which we can extend
            existing_allocation_start_addr = (
                self._get_containing_or_neighboring_allocation(vaddr)
            )
            if existing_allocation_start_addr is not None:
                # Extend the size!
                old_size = len(self.allocations[existing_allocation_start_addr])
                old_end_address = existing_allocation_start_addr + old_size - 1
                new_end_address = vaddr + size - 1
                increase = new_end_address - old_end_address
                # If there is actually something to increase, append empty bytes
                if increase > 0:
                    self.allocations[existing_allocation_start_addr].extend(
                        bytes(increase)
                    )
            else:
                # Add a new allocation
                bisect.insort(self.allocation_addresses, vaddr)
                # Initialize the bytearray as empty!
                self.allocations[vaddr] = bytearray(bytes(size))

    def _get_next_free_address(self) -> int:
        """
        Returns the next free address that can be allocated
        """
        with self.allocation_lock:
            if not self.allocation_addresses:
                return 0

            last_start = self.allocation_addresses[-1]
            last_size = len(self.allocations[last_start])

            return last_start + last_size

    def _memory_is_allocated(self, vaddr: int, size: int) -> bool:
        """
        Returns whether any memory was allocated that covers the given size in bytes
        starting from the given vaddr
        """
        return self._get_containing_allocation(vaddr, size) is not None

    def _bool_to_byte(self, value: bool) -> bytes:
        transformed_value = 0
        if value:
            transformed_value = 1
        return transformed_value.to_bytes(1, BYTE_ORDER)

    def _get_ctrl_bytes(
        self, is_write: bool, address: int, data: bytearray, do_polling: bool
    ) -> bytes:
        """
        Returns the byte for a single ctrl read/write
        """
        assert len(data) <= 8, "AXI control register support at most 8 bytes of data"
        return struct.pack(
            f"{self.byte_order}cqqc",
            self._bool_to_byte(is_write),
            address,
            int.from_bytes(data, BYTE_ORDER),
            self._bool_to_byte(do_polling),
        )

    def _get_mem_bytes(self, vaddr: int, size_in_bytes: int) -> bytes:
        """
        Returns the bytes for the socket message to perform a memory operation
        """
        return struct.pack(f"{self.byte_order}qq", vaddr, size_in_bytes)

    def _get_invoke_bytes(
        self,
        op_code: CoyoteOperator,
        stream_type: CoyoteStreamType,
        dest_coyote_stream: int,
        vaddr: int,
        len: int,
        last: bool,
    ) -> bytes:
        """
        Returns the bytes for the socket message to invoke a transfer
        """
        return struct.pack(
            f"{self.byte_order}cccqqc",
            op_code.value.to_bytes(1, BYTE_ORDER),
            stream_type.value.to_bytes(1, BYTE_ORDER),
            dest_coyote_stream.to_bytes(1, BYTE_ORDER),
            vaddr,
            len,
            self._bool_to_byte(last),
        )

    def _get_check_completed_bytes(
        self, op_code: CoyoteOperator, count: int, do_polling: bool
    ):
        return struct.pack(
            f"{self.byte_order}cqc",
            op_code.value.to_bytes(1, BYTE_ORDER),
            count,
            self._bool_to_byte(do_polling),
        )

    def _get_ctrl_reg_id(self, config: FPGAConfiguration) -> int:
        # We need to shift the ID by 3
        # because the IDs address bytes and there are 2^3 or 8 bytes
        # in one register. -> This is the coarsest possible addressing.
        return config.id() << 3

    def _get_ctrl_data(self, config: FPGAConfiguration) -> bytearray:
        data = config.value()
        if isinstance(data, bool):
            return bytearray([1 if data else 0])
        return data

    def _write_message_type(self, message_type: SocketSendMessageType) -> None:
        type_packed = struct.pack(
            f"{self.byte_order}c", message_type.value.to_bytes(1, BYTE_ORDER)
        )
        self.input_queue.put(type_packed)

    def _write_input(
        self, message_type: SocketSendMessageType, *data: List[Union[bytes, bytearray]]
    ) -> None:
        """
        Writes a message type and the given data to the fifo
        """
        self._write_message_type(message_type)
        for input in data:
            self.input_queue.put(input)

    #
    # Public methods
    #
    def register_interrupt_handler(self, handler: Callable[[int, int], None]):
        """
        Sets a callable function that will be invoked whenever a interrupt is
        received from the FPGA. The function should accept two integer values:
            1. The pid of the process begin invoked
            2. The value of the invocation

        The function will be executed in its own thread so it can perform blocking
        operations and invoke functions on this io_writer.

        However, note, that output processing is blocked while the handler is begin
        invoked.

        Should the handler throw an error this is considered fatal and will terminate
        the test case.
        """
        sig = inspect.signature(handler)
        parameter_count = len(sig.parameters)
        assert parameter_count == 2, (
            f"Expected interrupt handler to accept two integer parameters. Found handler with {parameter_count} parameters"
        )
        self.interrupt_handler = handler

    def ctrl_write(self, config: FPGAConfiguration) -> None:
        """
        Write the given value to the specified register id in the simulation
        """
        self.logger.info(f"Writing CTRL {str(config)}")
        self._write_input(
            SocketSendMessageType.CONTROL,
            self._get_ctrl_bytes(
                True, self._get_ctrl_reg_id(config), self._get_ctrl_data(config), False
            ),
        )

    def all_input_done(self) -> None:
        """
        Flushes all previously written commands and then closes
        the stream to the input file.

        This needs to be done for the simulation to finish!

        Since the simulation cannot know how much input is expected,
        it waits till the file receives a EOF.
        """
        self.logger.info("Input was marked as done")
        self.input_done_event.set()

    # TODO: Implement
    def ctrl_read():
        pass

    # TODO: Implement
    def ctrl_poll():
        pass

    def allocate_sim_memory(self, vaddr: int, size: int) -> None:
        """
        Allocates new memory in the simulation at the given vaddr and size
        """
        self.logger.info(f"Allocating memory at vaddr {vaddr} with size {size}")
        # We always allocate at least one byte!
        assert size >= 0, f"Cannot allocate a negative amount of bytes. Got {size}"
        if size == 0:
            size = 1
        self._write_input(
            SocketSendMessageType.GET_MEMORY, self._get_mem_bytes(vaddr, size)
        )
        self._add_memory_allocation(vaddr, size)

    def sleep(self, cycles: int):
        """
        Delays the the processing or further simulation commands by the
        given number of cycles
        """
        self.logger.info(f"Triggering sleep for {cycles} cycles")
        self._write_input(
            SocketSendMessageType.SLEEP,
            struct.pack(f"{self.byte_order}q", cycles),
        )

    def read_from_sim_memory(self, vaddr: int, size: int) -> bytearray:
        """
        Reads size bytes from the the simulation memory, starting at the
        given vadddr.

        Note: The data at this address stems either from a transfer
              or was written using the 'write_to_sim_memory' method.
        """
        self.logger.info(f"Reading {size} bytes from sim memory at vaddr {vaddr}")
        with self.allocation_lock:
            # Check that this memory has been allocated
            start_address = self._get_containing_allocation(vaddr, size)
            assert start_address is not None, (
                f"Could not read {size} bytes from vaddr {vaddr} as it was not allocated."
                + self._get_allocated_memory_properties()
            )

            # Read the data
            relative_index = vaddr - start_address
            return self.allocations[start_address][
                relative_index : relative_index + size
            ]

    def write_to_sim_memory(self, vaddr: int, data: bytearray) -> None:
        """
        Writes the given data to the simulation memory at the given vaddr
        """
        self.logger.info(
            f"Writing {len(data)} bytes to sim memory, starting from vaddr {vaddr}"
        )
        # TODO: Write to memory!!
        assert self._memory_is_allocated(vaddr, len(data)), (
            f"Could not write {len(data)} bytes to vaddr {vaddr} as it was not allocated"
            + self._get_allocated_memory_properties()
        )

        self._write_input(
            SocketSendMessageType.WRITE_MEMORY,
            self._get_mem_bytes(vaddr, len(data)),
            data,
        )

    def allocate_next_free_sim_memory(self, len: int) -> int:
        """
        Allocates the len bytes from the next free memory in the simulation.
        Returns the vaddr of the first allocated byte
        """
        next_address = self._get_next_free_address()
        self.allocate_sim_memory(next_address, len)
        return next_address

    def allocate_and_write_to_next_free_sim_memory(self, data: bytearray) -> int:
        """
        Convenience function that performs the following actions:
        - Allocates memory of the FPGA that exactly fits the given bytearray
        - Write the given bytearray to this memory
        - Returns the vaddr of the first byte written
        """
        next_address = self.allocate_next_free_sim_memory(len(data))
        self.write_to_sim_memory(next_address, data)
        return next_address

    def invoke_transfer(
        self,
        op_code: CoyoteOperator,
        stream_type: CoyoteStreamType,
        dest_coyote_stream: int,
        vaddr: int,
        len: int,
        last: bool,
    ) -> None:
        """
        Invokes a transfer from the simulation memory to the FPGA.
        Ensures the memory at the given vaddr and length has been allocated
        and the stream is is not out of bounds.
        """
        assert isinstance(vaddr, int)
        assert isinstance(len, int) and len >= 0
        assert dest_coyote_stream < MAX_NUMBER_STREAMS and dest_coyote_stream >= 0, (
            f"The design was set to support only {MAX_NUMBER_STREAMS} streams. You send invoke for stream with id {dest_coyote_stream}."
        )
        assert self._memory_is_allocated(vaddr, len), (
            f"Could not invoke transfer over {len} bytes to vaddr {vaddr} as it was not allocated."
            + self._get_allocated_memory_properties()
        )
        self.logger.info(
            f"Invoking transfer. Oper: {op_code}; Stream: {stream_type}; Coyote stream: {dest_coyote_stream}; Vaddr: {vaddr}; Len: {len}; Last: {last}"
        )

        self._write_input(
            SocketSendMessageType.INVOKE,
            self._get_invoke_bytes(
                op_code, stream_type, dest_coyote_stream, vaddr, len, last
            ),
        )

    def check_completed(
        self, op_code: CoyoteOperator, stop_event: threading.Event = None
    ) -> int:
        """
        Returns the number of completed transfers for the given Coyote Operator.
        Note: This call is blocking until the simulation responds with the completed count.
        Note: Only invocations/transfers with last = True will increase the completed count.

        Optionally, a early termination event can be provided. If this is given, the event is checked
        periodically and waiting for the output is canceled when the event is set. In this case,
        None will be returned!
        """
        self.logger.info(f"Fetching number of completed operators for {op_code.name}")
        self._write_input(
            SocketSendMessageType.CHECK_COMPLETION,
            self._get_check_completed_bytes(op_code, 0, False),
        )

        return self._try_dequeue_till_stop(
            self.check_completed_output_queue, stop_event
        )

    def block_till_completed(
        self, op_code: CoyoteOperator, count: int, stop_event: threading.Event = None
    ) -> None:
        """
        Blocking call that returns when the provided CoyoteOperator was completed at least count times.
        Note: This call stalls any IO processing (e.g. those commands written to the simulation
              via this class) in the simulation until the number of completions is reached.
              This means any IO command triggered in between starting and finishing this call
              will not be processed until after the call is finished. In order words, you
              should ensure the appropriate transfers have been triggered BEFORE performing this call.
        Note: Only invocations/transfers with last = True will increase the completed count. If you
              perform transfers without last = True ensure those are NOT included in 'count'.

        Optionally, a early termination event can be provided. If this is given, the event is checked
        periodically and waiting for the output is canceled when the event is set.
        """
        self.logger.info(f"Waiting till {op_code.name} completed {count} times")
        self._write_input(
            SocketSendMessageType.CHECK_COMPLETION,
            self._get_check_completed_bytes(op_code, count, True),
        )
        # Wait until we get the response that the number of completions was reached!
        actualCount = self._try_dequeue_till_stop(
            self.check_completed_output_queue, stop_event
        )
        if actualCount:
            self.logger.info(f"Got {count} completions of {op_code.name}.")
            # Sanity check that the waiting completed as expected!
            assert actualCount >= count, (
                f"Unexpected Error: Waited for at least {count} completions of {op_code.name} but got {actualCount}"
            )
        else:
            self.logger.info(
                f"Waiting for {count} completions of {op_code.name} was cancelled"
            )
