from enum import Enum
from typing import Union, List
from .constants import BYTE_ORDER
import struct
from .utils.list_util import split_into_batches
from .utils.bool_util import bools_to_bytearray


# Note: When adding a new stream type, please also implement the output functions
# for this type in output_comparison.py -> _write_diff_files_for_stream_type.
class StreamType(Enum):
    SIGNED_INT_32 = 0
    SIGNED_INT_64 = 1
    FLOAT_64 = 2
    FLOAT_32 = 3
    UNSIGNED_INT_8 = 4
    UNSIGNED_INT_16 = 5
    UNSIGNED_INT_32 = 6
    UNSIGNED_INT_64 = 7
    SIGNED_INT_8 = 8
    SIGNED_INT_16 = 9
    # Booleans according to the Arrow storage format.
    # Each boolean will take 1 bit and all booleans are packed from LSB to MSB.
    ARROW_BOOL = 10


def get_bytes_for_stream_type(stream_type: StreamType) -> int:
    match stream_type:
        case StreamType.UNSIGNED_INT_8 | StreamType.SIGNED_INT_8:
            return 1
        case StreamType.UNSIGNED_INT_16 | StreamType.SIGNED_INT_16:
            return 2
        case (
            StreamType.UNSIGNED_INT_32 | StreamType.SIGNED_INT_32 | StreamType.FLOAT_32
        ):
            return 4
        case (
            StreamType.UNSIGNED_INT_64 | StreamType.SIGNED_INT_64 | StreamType.FLOAT_64
        ):
            return 8


def is_int_type(stream_type: StreamType) -> bool:
    match stream_type:
        case (
            StreamType.UNSIGNED_INT_8
            | StreamType.SIGNED_INT_8
            | StreamType.UNSIGNED_INT_16
            | StreamType.SIGNED_INT_16
            | StreamType.UNSIGNED_INT_32
            | StreamType.SIGNED_INT_32
            | StreamType.UNSIGNED_INT_64
            | StreamType.SIGNED_INT_64
        ):
            return True
        case _:
            return False


def is_int_type_signed(stream_type: StreamType) -> bool:
    match stream_type:
        case (
            StreamType.SIGNED_INT_8
            | StreamType.SIGNED_INT_16
            | StreamType.SIGNED_INT_32
            | StreamType.SIGNED_INT_64
        ):
            return True
        case _:
            return False


def is_float_type(stream_type: StreamType) -> bool:
    match stream_type:
        case StreamType.FLOAT_32 | StreamType.FLOAT_64:
            return True
        case _:
            return False


def is_bool_type(stream_type: StreamType) -> bool:
    match stream_type:
        case StreamType.ARROW_BOOL:
            return True
        case _:
            return False


def get_struct_format_char_for_float(stream_type: StreamType) -> str:
    match stream_type:
        case StreamType.FLOAT_32:
            return "f"
        case StreamType.FLOAT_64:
            return "d"
        case _:
            raise ValueError(
                f"Got non float type {stream_type.name} for 'get_struct_format_char_for_float' call“"
            )

def get_struct_prefix_for_byte_order():
    return "<" if BYTE_ORDER == "little" else ">"

def convert_data_elem_to_bytearray_for_stream_type(
    data: Union[int, float], stream_type: StreamType
):
    bytearr = bytearray()

    if is_int_type(stream_type):
        width_in_bytes = get_bytes_for_stream_type(stream_type)
        is_signed = is_int_type_signed(stream_type)
        bytearr.extend(
            data.to_bytes(width_in_bytes, byteorder=BYTE_ORDER, signed=is_signed)
        )
    elif is_float_type(stream_type):
        format_char = get_struct_format_char_for_float(stream_type)
        prefix = get_struct_prefix_for_byte_order()
        pack_modifier = f"{prefix}{format_char}"
        bytearr.extend(struct.pack(pack_modifier, data))
    else:
        raise ValueError(f"Unsupported StreamType {stream_type}")

    return bytearr


def convert_data_to_bytearray_for_stream_type(
    data: Union[List[int], List[bool], List[float]], stream_type: StreamType
) -> bytearray:
    if is_int_type(stream_type) or is_float_type(stream_type):
        # Convert the data element-wise
        bytearr = bytearray()
        for element in data:
            bytearr.extend(
                convert_data_elem_to_bytearray_for_stream_type(element, stream_type)
            )
        return bytearr
    elif is_bool_type(stream_type):
        # Convert the whole list directly
        return bools_to_bytearray(data, BYTE_ORDER)
    else:
        raise ValueError(f"Unsupported StreamType {stream_type}")


def is_int_within_bounds(bits: int, value: int):
    min_int = -1 * pow(2, bits - 1)
    max_int = pow(2, bits - 1) - 1
    return value >= min_int and value <= max_int


class Stream:
    """
    Helper class describing a data stream to the FPGA of a specific
    StreamType. Handles the conversion from python types into the
    proper binary representation and performs bound checks for integers.
    """

    def __init__(self, data_type: StreamType, data: Union[List[int], List[float], List[bool]]):
        self.data_type = data_type

        # Assert all the data items are of the correct type
        if is_int_type(data_type):
            assert isinstance(data, list) and all(isinstance(x, int) for x in data), (
                f"Cannot accept non integer data for stream of type {data_type.name}. Got the following list {data}"
            )
            # Do a bounds check
            size_bits = get_bytes_for_stream_type(data_type) * 8
            assert all(is_int_within_bounds(size_bits, x) for x in data), (
                f"Cannot accept {data_type.name} values that are out of the value range. Got {data}"
            )
        elif is_float_type(data_type):
            assert isinstance(data, list) and all(isinstance(x, float) for x in data), (
                f"Cannot accept non float data for stream of type {data_type.name}. Got {data}"
            )
        elif is_bool_type(data_type):
            assert isinstance(data, list) and all(isinstance(x, bool) for x in data), (
                f"Cannot accept non bool data for stream of type {data_type.name}. Got {data}"
            )
        else:
            raise ValueError(f"Unknown data type for column: {data_type}")

        self.data = data

    def stream_data(self) -> Union[List[int], List[float], List[bool]]:
        return self.data

    def stream_type(self) -> StreamType:
        return self.data_type


    def data_to_bytearray(self) -> bytearray:
        """
        Returns the data converted to a bytearray to be send to the FPGA
        """
        return convert_data_to_bytearray_for_stream_type(self.data, self.data_type)

    def data_split_into_batches(
        self, num_batches: int
    ) -> Union[List[int], List[float], List[bool]]:
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
            convert_data_to_bytearray_for_stream_type(batch, self.data_type)
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
