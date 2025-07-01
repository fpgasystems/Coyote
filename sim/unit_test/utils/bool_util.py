from typing import List, Literal

def bools_to_bytearray(booleans: List[bool], byte_order: Literal["little", "big"] = "little") -> bytearray:
    assert(len(booleans) % 8 == 0) # Needs to be split-able in bytes
    assert byte_order == "little", "Big endian is not yet supported for 'bools_to_bytearray'"
    bytearr = bytearray(len(booleans) // 8)
    for index, mask in enumerate(booleans):
        if mask:
            # Set the bit if True
            # Note: We store the bits little-endian.
            # -> The least significant index is stored first
            bytearr[index // 8] |= (1 << (index % 8))

    return bytearr