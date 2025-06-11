from typing import Union
import struct
from .constants import BYTE_ORDER

class FPGAConfiguration():
    def __init__(self, id : int, value: Union[bool, bytearray]):
        """
        Instantiates a new FPGAConfiguration instance that has a register id and the register value
        """
        self._id = id
        assert isinstance(value, bool) or isinstance(value, bytearray), \
            f"FPGAConfiguration can only work with the types boolean or bytearray directly. Got: {type(value)}"
        self._value = value

    def id(self) -> int:
        return self._id

    def value(self) -> Union[bool, bytearray]:
        return self._value

    def __str__(self):
        if isinstance(self._value, bytearray):
            as_int = int.from_bytes(self._value, BYTE_ORDER, signed=True)
            if len(self._value) == 8:
                as_double = struct.unpack(f"{'<' if BYTE_ORDER == 'little' else '>'}d", self._value)[0]
            else:
                as_double = 0.0
            byte_repr = ' '.join(f'{byte:02x}' for byte in self._value)
            rev_byte_repr = ' '.join(f'{byte:02x}' for byte in reversed(self._value))
            if BYTE_ORDER == "little":
                byte_prefix = "(LSB) -> (MSB) (for FPGA)"
                rev_byte_prefix = "(MSB) -> (LSB) (in C++)"
            else:
                byte_prefix = "(MSB) -> (LSB) (for FPGA)"
                rev_byte_prefix = "(LSB) -> (MSB) (reversed)"
            return f"FPGARegister {{.id = {self._id}, .value=\nbytes:" + \
                   f"\t\t{byte_prefix}\n\t\t{byte_repr}\n"+ \
                   f"\t\t{rev_byte_prefix}\n\t\t{rev_byte_repr}\n"+ \
                   f"signed int:\t{as_int}\ndouble:\t\t{as_double}\n}}"
        else:
            return f"FPGARegister {{.id = {self._id}, .value={self._value}}}"