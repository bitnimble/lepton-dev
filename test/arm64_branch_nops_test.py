import os
import struct
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addon"))
import arm64_branch_nops as patcher  # noqa: E402

NOP, RET = 0xD503201F, 0xD65F03C0
CODE = 0x80


def b(delta):
    return 0x14000000 | (delta // 4 & 0x3FFFFFF)


def b_eq(delta):
    return 0x54000000 | (delta // 4 & 0x7FFFF) << 5


def tbz(delta):
    return 0x36000000 | (delta // 4 & 0x3FFF) << 5


def elf(words, data_words):
    """Code words in an executable .text section, followed by data words in the same segment."""
    code = struct.pack(f"<{len(words)}I", *words)
    tail = struct.pack(f"<{len(data_words)}I", *data_words)
    shoff = CODE + len(code) + len(tail)
    header = bytearray(CODE)
    header[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<H", header, 0x12, 183)
    struct.pack_into("<Q", header, 0x20, 64)
    struct.pack_into("<Q", header, 0x28, shoff)
    struct.pack_into("<HH", header, 0x36, 56, 1)
    struct.pack_into("<HH", header, 0x3A, 64, 2)
    struct.pack_into("<IIQQQQ", header, 64, 1, 5, CODE, CODE, CODE, len(code) + len(tail))
    sections = bytearray(128)
    struct.pack_into("<IIQQQQ", sections, 64, 1, 1, 0x6, CODE, CODE, len(code))
    return bytes(header) + code + tail + bytes(sections)


def words_of(path, count):
    with open(path, "rb") as handle:
        data = handle.read()
    return list(struct.unpack_from(f"<{count}I", data, CODE))


# 0x00 b 0x08 | 0x04 ret | 0x08 nop | 0x0c nop | 0x10 ret | 0x14 b.eq 0x08 | 0x18 tbz 0x08 | 0x1c b 0x04
# | 0x20 cbz 0x0c, then data outside .text: a word shaped like b -4 onto the nop at 0x24... (stays)
before = [b(8), RET, NOP, NOP, RET, b_eq(-12), tbz(-16), b(-24), 0xB4000000 | (-0x14 // 4 & 0x7FFFF) << 5]
after = [b(16), RET, NOP, NOP, RET, b_eq(-4), tbz(-8), b(-24), 0xB4000000 | (-0x10 // 4 & 0x7FFFF) << 5]
data = [NOP, b(-4)]

with tempfile.TemporaryDirectory() as directory:
    path = os.path.join(directory, "libtest.so")
    with open(path, "wb") as handle:
        handle.write(elf(before, data))
    assert patcher.process(path, patch=True) == 4, "four jumps land on NOPs"
    patched = words_of(path, len(before) + len(data))
    assert patched == after + data, f"retargeted past the NOPs, data untouched: {[hex(w) for w in patched]}"
    assert patcher.process(path, patch=True) == 0, "a second pass changes nothing"
print("arm64_branch_nops_test: all passed")
