from enum import Enum
from typing import Union, List
from .constants import BYTE_ORDER
import struct
from .utils.list_util import split_into_batches


class StreamType(Enum):
    SIGNED_INT_32 = 0
    SIGNED_INT_64 = 1
    FLOAT_64 = 2


def convert_data_to_bytearray_for_stream_type(
    data: Union[int, float], column_type: StreamType
) -> bytearray:
    bytearr = bytearray()

    if (
        column_type == StreamType.SIGNED_INT_32
        or column_type == StreamType.SIGNED_INT_64
    ):
        width_in_bytes = 4 if column_type == StreamType.SIGNED_INT_32 else 8
        bytearr.extend(data.to_bytes(width_in_bytes, byteorder=BYTE_ORDER, signed=True))
    elif column_type == StreamType.FLOAT_64:
        pack_modifier = "<d" if BYTE_ORDER == "little" else ">d"
        bytearr.extend(struct.pack(pack_modifier, data))
    else:
        raise ValueError(f"Unsupported ColumnType {column_type}")

    return bytearr


def int32_within_bounds(value: int) -> bool:
    min_int = -1 * pow(2, 31)
    max_int = pow(2, 31) - 1
    return value >= min_int and value <= max_int


def int64_within_bounds(value: int) -> bool:
    min_int = -1 * pow(2, 63)
    max_int = pow(2, 63) - 1
    return value >= min_int and value <= max_int


class Stream:
    """
    Helper class describing a data stream to the FPGA of a specific
    StreamType. Handles the conversion from python types into the
    proper binary representation and performs bound checks for integers.
    """

    def __init__(self, data_type: StreamType, data: Union[List[int], List[float]]):
        self.data_type = data_type

        # Assert all the data items are of the correct type
        if (
            data_type == StreamType.SIGNED_INT_32
            or data_type == StreamType.SIGNED_INT_64
        ):
            assert isinstance(data, list) and all(isinstance(x, int) for x in data), (
                f"Cannot accept non integer data for stream of type {data_type.name}. Got the following list {data}"
            )
            # Assert value ranges for the integer types
            if data_type == StreamType.SIGNED_INT_32:
                assert all(int32_within_bounds(x) for x in data), (
                    f"Cannot accept 32 values that are out of the value range. Got {data}"
                )
            else:
                assert all(int64_within_bounds(x) for x in data), (
                    f"Cannot accept 32 values that are out of the value range. Got {data}"
                )
        elif data_type == StreamType.FLOAT_64:
            assert isinstance(data, list) and all(isinstance(x, float) for x in data), (
                f"Cannot accept non float data for stream of type {data_type.name}."
            )
        else:
            raise ValueError(f"Unknown data type for column: {data_type}")

        self.data = data

    def stream_data(self) -> Union[List[int], List[float]]:
        return self.data

    def stream_type(self) -> StreamType:
        return self.data_type

    def _convert_data_array_to_bytearray(self, data, data_type):
        bytearr = bytearray()

        for element in data:
            bytearr.extend(
                convert_data_to_bytearray_for_stream_type(element, data_type)
            )

        return bytearr

    def data_to_bytearray(self) -> bytearray:
        """
        Returns the data converted to a bytearray to be send to the FPGA
        """
        return self._convert_data_array_to_bytearray(self.data, self.data_type)

    def data_split_into_batches(
        self, num_batches: int
    ) -> Union[List[int], List[float]]:
        """
        Returns the data split into 'num_batches' batches
        """
        return list(split_into_batches(self.data, num_batches))

    def data_to_batched_bytearray(self, num_batches: int) -> List[bytearray]:
        """
        Splits the data into the given number of batches and then returns
        it as a bytearray
        """
        batches = self.data_split_into_batches(num_batches)
        return [
            self._convert_data_array_to_bytearray(batch, self.data_type)
            for batch in batches
        ]

    def __iter__(self):
        return self.data.__iter__()

    def __next__(self):
        return self.data.__next__()

    def __hash__(self):
        return hash(tuple(self.data))

    def length(self):
        return len(self.data)

    def __str__(self):
        return f"Stream {{.data_type={self.data_type}, .data={self.data}}}"
