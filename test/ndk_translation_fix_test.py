import os
import subprocess
import sys
import tempfile

ADDON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addon", "ndk-translation")
sys.path.insert(0, ADDON)
import fix  # noqa: E402

with tempfile.TemporaryDirectory() as directory:
    for source, _, size, code in fix.PATCHES:
        obj, binary = os.path.join(directory, "f.o"), os.path.join(directory, "f.bin")
        subprocess.run(["as", "--64", "-o", obj, os.path.join(ADDON, source)], check=True)
        subprocess.run(["objcopy", "-O", "binary", "-j", ".text", obj, binary], check=True)
        with open(binary, "rb") as handle:
            assembled = handle.read()
        assert len(assembled) <= size, f"{source}: {len(assembled)} bytes overflow its {size}-byte slot"
        assert code == assembled, f"fix.py's bytes match {source}"

original = bytes(range(256)) * 0x1000
patched = fix.fixed(original)
assert len(patched) == len(original), "same size"
slots = [(offset, offset + size) for _, offset, size, _ in fix.PATCHES]
outside = [i for i in range(0, len(original), 97) if not any(start <= i < end for start, end in slots)]
assert all(patched[i] == original[i] for i in outside), "only the slots change"
assert patched[0xD49A0 + 31:0xD49A0 + 0x8E] == b"\xcc" * (0x8E - 31), "slot tail is int3"
print("ndk_translation_fix_test: all passed")
