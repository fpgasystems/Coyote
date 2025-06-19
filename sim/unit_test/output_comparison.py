import os
from pathlib import Path
import struct
from typing import Optional, Union
import logging

from .fpga_stream import (
    StreamType,
    is_int_type,
    get_bytes_for_stream_type,
    is_int_type_signed,
    is_float_type,
    is_bool_type,
    get_struct_format_char_for_float,
    get_struct_prefix_for_byte_order,
)
from .constants import BYTE_ORDER, DIFF_FOLDER

DIFF_EXPECTED = os.path.join(DIFF_FOLDER, "{test}_{vaddr}_{index}_{type}_expected.txt")
DIFF_ACTUAL = os.path.join(DIFF_FOLDER, "{test}_{vaddr}_{index}_{type}_actual.txt")


class OutputComparator:
    def __init__(self, test_method_name: str):
        self._test_method_name = test_method_name
        self.logger = logging.getLogger("OutputComparator")

    #
    # Private methods
    #

    def _write_to_diff(
        self, expected: bytearray, actual: bytearray, vaddr: int, stream: int, file_type
    ):
        # Get file names
        stream_str = str(stream) if stream is not None else ""
        expected_target_file = DIFF_EXPECTED.format(
            test=self._test_method_name, vaddr=vaddr, index=stream_str, type=file_type
        )
        actual_target_file = DIFF_ACTUAL.format(
            test=self._test_method_name, vaddr=vaddr, index=stream_str, type=file_type
        )

        # Ensure the path exists
        dir_path = Path(expected_target_file)
        os.makedirs(dir_path.parent, exist_ok=True)

        # Write the diff to the output file
        with open(expected_target_file, "w") as f:
            f.writelines(expected)

        with open(actual_target_file, "w") as f:
            f.writelines(actual)

    def _write_diff_binary(
        self, expected: bytearray, actual: bytearray, vaddr: int, stream: int
    ):
        # Convert bytes to string for readable diff output
        expected = "Expected: \n\n" + "".join(
            f"{index:05d}: {byte:08b} ({byte})\n" for index, byte in enumerate(expected)
        )
        actual = (
            "Actual: \n"
            + "Be aware: a zero does not necessarily mean the design produced a output "
            + "that was zero. Zero is also the default value for newly allocated memory. "
            + "Please check the logs.\n"
            + "".join(
                f"{index:05d}: {byte:08b} ({byte})\n"
                for index, byte in enumerate(actual)
            )
        )

        self._write_to_diff(expected, actual, vaddr, stream, "byte")

    def _write_diff_int_with_n_bytes(
        self,
        n_bytes: int,
        is_signed: bool,
        expected: bytearray,
        actual: bytearray,
        vaddr: int,
        stream: int,
    ):
        expected_i = []
        for elem in range(0, len(expected) // n_bytes):
            int_from_bytes = int.from_bytes(
                expected[elem * n_bytes : (elem + 1) * n_bytes],
                BYTE_ORDER,
                signed=is_signed,
            )
            expected_i.append(int_from_bytes)

        actual_i = []
        for elem in range(0, len(actual) // n_bytes):
            int_from_bytes = int.from_bytes(
                actual[elem * n_bytes : (elem + 1) * n_bytes],
                BYTE_ORDER,
                signed=is_signed,
            )
            actual_i.append(int_from_bytes)

        # Convert bytes to string for readable diff output
        expected = "Expected: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(expected_i)
        )
        actual = "Actual: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(actual_i)
        )

        self._write_to_diff(expected, actual, vaddr, stream, f"int{n_bytes * 8}")

    def _write_diff_float(
        self,
        stream_type: StreamType,
        expected: bytearray,
        actual: bytearray,
        vaddr: int,
        stream: int,
    ):
        n_bytes =  get_bytes_for_stream_type(stream_type)
        format_char = get_struct_format_char_for_float(stream_type)
        prefix = get_struct_prefix_for_byte_order()

        expected_num = len(expected) // n_bytes
        expected_fp = struct.unpack(f"{prefix}{expected_num}{format_char}", expected)

        actual_num = len(actual) // n_bytes
        actual_fp = struct.unpack(f"{prefix}{actual_num}{format_char}", actual)

        # Convert bytes to string for readable diff output
        expected = "Expected: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(expected_fp)
        )
        actual = "Actual: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(actual_fp)
        )

        self._write_to_diff(expected, actual, vaddr, stream, f"fp{n_bytes * 8}")

    def _write_diff_files_for_stream_type(
        self,
        expected: bytearray,
        actual: bytearray,
        vaddr: int,
        stream: Optional[int],
        stream_type: StreamType,
    ):
        n_bytes = get_bytes_for_stream_type(stream_type)
        error_message = (
            f"for vaddr {vaddr} & stream {stream} was supposed "
            + f"to be {stream_type.name} with {n_bytes} per element but output had length "
            + "{length}"
            + f", which is not dividable by {n_bytes}."
        )

        # Check the expected output length
        assert len(expected) % n_bytes == 0, (
            f"Expected output {error_message.format(length=len(expected))}"
        )

        # Check the actual output length
        if len(actual) % n_bytes != 0:
            self.logger.warning(
                f"Actual output {error_message.format(length=len(actual))}. A byte diff will be generated instead."
            )
            self._write_diff_binary(expected, actual, vaddr, stream)
            return

        # The sizes all match! -> Write the diff output
        if is_int_type(stream_type):
            is_signed = is_int_type_signed(stream_type)
            self._write_diff_int_with_n_bytes(
                n_bytes, is_signed, expected, actual, vaddr, stream
            )
        elif is_float_type(stream_type):
            self._write_diff_float(stream_type, expected, actual, vaddr, stream)
        else:
            raise ValueError(f"Unsupported StreamType {stream_type}")

    def _write_diff_files(
        self,
        expected: bytearray,
        actual: bytearray,
        vaddr: int,
        stream: Optional[int],
        stream_type: Optional[StreamType],
    ):
        # Write the diff file based on the stream type
        if stream_type is None or is_bool_type(stream_type):
            self._write_diff_binary(expected, actual, vaddr, stream)
        else:
            self._write_diff_files_for_stream_type(
                expected, actual, vaddr, stream, stream_type
            )

    #
    # Public methods
    #
    def clean_previous_diffs(self):
        """
        Cleans the directory of diff files from potential, previous outputs
        """
        # Remove old diff files from the diff folder
        for file in Path(DIFF_FOLDER).glob("*.txt"):
            file.unlink()

    def bitwise_compare_outputs(
        self,
        expected: bytearray,
        actual: bytearray,
        vaddr: int,
        stream: Optional[Union[int, str]] = None,
        stream_type: Optional[StreamType] = None,
    ):
        """
        Bitwise compares the two bytearrays.
        Produces a diff file inside the UNIT_TEST folder should not be equal.
        Raises a AssertionError if the comparison fails.
        """
        if expected is None:
            self.assertTrue(len(actual) == 0)
        else:
            try:
                assert expected == actual, (
                    f"\nExpected output and actual output are not equal for stream {stream}. Look at the diff files to find the difference"
                )
            except AssertionError as err:
                # Generate diff files
                self._write_diff_files(expected, actual, vaddr, stream, stream_type)
                raise err
