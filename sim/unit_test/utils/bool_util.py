from typing import List

def bools_to_bytearray(booleans: List[bool]) -> bytearray:
    assert(len(booleans) % 8 == 0) # Needs to be split-able in bytes
    bytearr = bytearray(len(booleans) // 8)
    for index, mask in enumerate(booleans):
        if mask:
            # Set the bit if True
            # Note: Order needs to be normal byte order (from MSB to LSB)
            bytearr[index // 8] |= (1 << (index % 8))

    return bytearr