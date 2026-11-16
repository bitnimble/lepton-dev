#!/usr/bin/env python3
"""Retargets ARM64 jumps that land on a NOP to the first instruction after the NOPs, in LIB_DIR/*.so.

The API 34 NDK translator's heavy optimizer can loop forever on a jump to a NOP, hanging a game in tiered mode.
Idempotent. With STAMPS (a file), libraries unchanged since they were last handled are skipped.
Usage: arm64_branch_nops.py patch|scan LIB_DIR [STAMPS]
"""
import json
import os
import struct
import sys

NOP = 0xD503201F
EM_AARCH64 = 183
SHF_EXECINSTR, SHT_NOBITS = 0x4, 8
# Tencent ACE anti-cheat: UNITE crashed with these modified
SKIP = {"libanogs.so", "libanort.so"}
# (mask, value, immediate's lowest bit, immediate's width) for B, B.cond, CBZ/CBNZ and TBZ/TBNZ.
JUMPS = (
    (0xFC000000, 0x14000000, 0, 26),
    (0xFF000010, 0x54000000, 5, 19),
    (0x7E000000, 0x34000000, 5, 19),
    (0x7E000000, 0x36000000, 5, 14),
)


def code_ranges(data):
    """File ranges of executable sections (code only, not data that shares their segment)."""
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return []
    if struct.unpack_from("<H", data, 0x12)[0] != EM_AARCH64:
        return []
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", data, 0x3A)
    ranges = []
    for index in range(shnum):
        base = shoff + index * shentsize
        if base + 64 > len(data):
            break
        _, sh_type, sh_flags, _, sh_offset, sh_size = struct.unpack_from("<IIQQQQ", data, base)
        if sh_flags & SHF_EXECINSTR and sh_type != SHT_NOBITS:
            start = sh_offset + (-sh_offset % 4)
            ranges.append((start, min(sh_offset + sh_size, len(data))))
    return ranges


def may_jump(word):
    """Cheap pre-filter for retarget, which is too slow to run on every word."""
    return word & 0xFC000000 == 0x14000000 or word & 0x7C000000 == 0x34000000 or word & 0xFF000010 == 0x54000000


def retarget(word, offset, data, start, end):
    """The jump at offset with its target moved past NOPs, or None if it doesn't land on one."""
    for mask, value, low, width in JUMPS:
        if word & mask != value:
            continue
        field = (word >> low) & ((1 << width) - 1)
        delta = (field - (1 << width) if field >> (width - 1) else field) * 4
        target = offset + delta
        moved = target
        while start <= moved < end - 3 and struct.unpack_from("<I", data, moved)[0] == NOP:
            moved += 4
        if moved == target or not start <= moved < end:
            return None
        field = (moved - offset) // 4
        if not -(1 << (width - 1)) <= field < 1 << (width - 1):
            return None
        return word & ~(((1 << width) - 1) << low) | (field & ((1 << width) - 1)) << low
    return None


def process(path, patch):
    with open(path, "rb") as handle:
        data = handle.read()
    changes = []
    for start, end in code_ranges(data):
        for index, (word,) in enumerate(struct.iter_unpack("<I", data[start:end - (end - start) % 4])):
            if not may_jump(word):
                continue
            offset = start + index * 4
            new = retarget(word, offset, data, start, end)
            if new is not None:
                changes.append((offset, new))
    if patch and changes:
        # in place (same inode), word by word: the library is in a live overlay
        fd = os.open(path, os.O_WRONLY)
        try:
            for offset, new in changes:
                os.pwrite(fd, struct.pack("<I", new), offset)
            os.fsync(fd)
        finally:
            os.close(fd)
    return len(changes)


def stamp(path):
    status = os.stat(path)
    return f"{status.st_size}:{status.st_mtime_ns}"


def main():
    if len(sys.argv) not in (3, 4) or sys.argv[1] not in ("patch", "scan"):
        print(__doc__, file=sys.stderr)
        return 2
    patch, lib_dir = sys.argv[1] == "patch", sys.argv[2]
    stamps_path = sys.argv[3] if len(sys.argv) == 4 else None
    stamps = {}
    if stamps_path and os.path.exists(stamps_path):
        with open(stamps_path, encoding="utf-8") as handle:
            stamps = json.load(handle)
    failed = False
    for name in sorted(os.listdir(lib_dir)):
        path = os.path.join(lib_dir, name)
        if name in SKIP or not name.endswith(".so") or not os.path.isfile(path) or os.path.islink(path):
            continue
        if stamps.get(path) == stamp(path):
            continue
        try:
            moved = process(path, patch)
        except (OSError, struct.error) as error:
            print(f"{name}: {error}", file=sys.stderr)
            failed = True
            continue
        if moved:
            print(f"{name}: {'moved' if patch else 'found'} {moved} jumps onto NOPs")
        if patch:
            stamps[path] = stamp(path)
    if stamps_path and patch:
        os.makedirs(os.path.dirname(stamps_path) or ".", exist_ok=True)
        with open(stamps_path, "w", encoding="utf-8") as handle:
            json.dump(stamps, handle)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
