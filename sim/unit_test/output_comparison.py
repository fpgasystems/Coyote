import os
from pathlib import Path
import struct
from typing import Optional, Union

from .constants import BYTE_ORDER, DIFF_FOLDER

DIFF_EXPECTED = os.path.join(DIFF_FOLDER, "{test}_{vaddr}_{index}_{type}_expected.txt")
DIFF_ACTUAL = os.path.join(DIFF_FOLDER, "{test}_{vaddr}_{index}_{type}_actual.txt")


class OutputComparator:
    def __init__(self, test_method_name: str):
        self._test_method_name = test_method_name

    #
    # Private methods
    #

    def _write_to_diff(self, expected: bytearray, actual: bytearray, vaddr: int, stream: int, file_type):
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

    def _write_diff_binary(self, expected: bytearray, actual: bytearray, vaddr: int, stream: int):
        # Convert bytes to string for readable diff output
        expected = "Expected: \n" + "".join(
            f"{index:05d}: {byte:08b} ({byte})\n" for index, byte in enumerate(expected)
        )
        actual = "Actual: \n" + "".join(
            f"{index:05d}: {byte:08b} ({byte})\n" for index, byte in enumerate(actual)
        )

        self._write_to_diff(expected, actual, vaddr, stream, "byte")

    def _write_diff_int_with_n_bytes(self, n_bytes: int, expected: bytearray, actual: bytearray, vaddr: int, stream: int):
        if len(expected) % n_bytes != 0 or len(actual) % n_bytes != 0:
            return

        expected_i = []
        for elem in range(0, len(expected) // n_bytes):
            int_from_bytes = int.from_bytes(
                expected[elem * n_bytes : (elem + 1) * n_bytes], BYTE_ORDER, signed=True
            )
            expected_i.append(int_from_bytes)

        actual_i = []
        for elem in range(0, len(actual) // n_bytes):
            int_from_bytes = int.from_bytes(
                actual[elem * n_bytes : (elem + 1) * n_bytes], BYTE_ORDER, signed=True
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


    def _write_diff_float64(self, expected: bytearray, actual: bytearray, vaddr: int, stream: int):
        if len(expected) % 8 != 0 or len(actual) % 8 != 0:
            return

        expected_num = len(expected) // 8
        expected_fp64 = struct.unpack(
            f"{'<' if BYTE_ORDER == 'little' else '>'}{expected_num}d", expected
        )

        actual_num = len(actual) // 8
        actual_fp64 = struct.unpack(
            f"{'<' if BYTE_ORDER == 'little' else '>'}{actual_num}d", actual
        )

        # Convert bytes to string for readable diff output
        expected = "Expected: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(expected_fp64)
        )
        actual = "Actual: \n" + "".join(
            f"{index:05d}: {elem}\n" for index, elem in enumerate(actual_fp64)
        )

        self._write_to_diff(expected, actual, vaddr, stream, "fp64")

    def _write_diff_files(self, expected: bytearray, actual: bytearray, vaddr: int, stream: int):
        self._write_diff_binary(expected, actual, vaddr, stream)
        self._write_diff_int_with_n_bytes(4, expected, actual, vaddr, stream)
        self._write_diff_int_with_n_bytes(8, expected, actual, vaddr, stream)
        self._write_diff_float64(expected, actual, vaddr, stream)

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
        self, expected: bytearray, actual: bytearray, vaddr: int, stream: Optional[Union[int, str]] = None
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
                self._write_diff_files(expected, actual, vaddr, stream)
                raise err
