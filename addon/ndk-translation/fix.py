#!/usr/bin/env python3
"""Writes a fixed copy of the API 34 r14 NDK translator into a Lepton rootfs overlay.

The heavy optimizer (tiered mode) can hang forever on a jump to an ARM64 NOP: UpdateBranchTargetsAfterSplit
misses branch targets that share the split position. The fix replaces that function (update_branch_targets.S)
and calls it from ResolveJumps, which had it inlined (resolve_jumps_call.S). Lepton bind-mounts the overlay over
the rootfs, and its NDK shim still checks the unmodified rootfs copy. Any other translator build removes a stale
fixed copy instead.
Usage: fix.py ROOTFS ROOTFS_OVERLAY
"""
import hashlib
import os
import sys
import tempfile

LIB = "system/lib64/libndk_translation.so"
REVIEWED_SHA256 = "a2086fbc807f697f9b91222065c9d9000ca9727748699c0d9b751319258cbb3e"
# (source, file offset, slot size, code); the rest of each slot becomes int3
PATCHES = (
    ("update_branch_targets.S", 0xD52A0, 0xB0, bytes.fromhex(
        "4c8d57284d8b024c89d04d85c074144939702072084c89c04d8b00ebed4d8b4008ebe74c39d074784839702075724c8b5830"
        "4989c14c3b4f2074344d8b014d85c0740e4d89c14d8b40084d85c075f4eb0c4d8b41104d39084d89c174f449395128750c4d"
        "395930750649894928ebc648395028752b488948284c8b40084d85c0740d4c89c04d8b004d85c075f5eb0c4c8b4010493900"
        "4c89c075f44c39d075cfc3")),
    ("resolve_jumps_call.S", 0xD49A0, 0x8E, bytes.fromhex(
        "4c89e6488b14244889c14989c4488b7c2408e8e90800004c89e0e96f000000")),
)


def fixed(original):
    data = bytearray(original)
    for _, offset, size, code in PATCHES:
        data[offset:offset + size] = code.ljust(size, b"\xcc")
    return bytes(data)


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    source, target = (os.path.join(root, LIB) for root in sys.argv[1:])
    original = b""
    if os.path.exists(source):
        with open(source, "rb") as handle:
            original = handle.read()
    if hashlib.sha256(original).hexdigest() != REVIEWED_SHA256:
        if os.path.exists(target):
            os.remove(target)
            print(f"removed {target}: the rootfs translator isn't the reviewed build")
        return 0
    data = fixed(original)
    if os.path.exists(target):
        with open(target, "rb") as handle:
            if handle.read() == data:
                return 0
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=os.path.dirname(target))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.chmod(temp, 0o644)
        os.replace(temp, target)
    except BaseException:
        os.remove(temp)
        raise
    print(f"wrote {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
