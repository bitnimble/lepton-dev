#!/usr/bin/env python3
"""Writes an ARM64 /proc/cpuinfo with one entry per host CPU into a Lepton rootfs overlay.

Android bind-mounts system/etc/cpuinfo.arm64.txt over /proc/cpuinfo for apps it runs through the ARM translator.
The rootfs copy describes a single CPU, so games size their thread pools and quality options for one core.
Usage: cpuinfo.py ROOTFS ROOTFS_OVERLAY
"""
import os
import sys
import tempfile

CPUINFO = "system/etc/cpuinfo.arm64.txt"


def expanded(template, cpus):
    block, _, trailer = template.partition("\n\n")
    lines = [line for line in block.splitlines() if not line.startswith("processor")]
    entries = ["\n".join([f"processor\t: {cpu}", *lines]) for cpu in range(cpus)]
    return "\n\n".join(entries) + "\n\n" + trailer.lstrip("\n")


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    source, target = (os.path.join(root, CPUINFO) for root in sys.argv[1:])
    if not os.path.exists(source):
        return 0
    with open(source) as handle:
        data = expanded(handle.read(), len(os.sched_getaffinity(0)))
    if os.path.exists(target):
        with open(target) as handle:
            if handle.read() == data:
                return 0
    os.makedirs(os.path.dirname(target), exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=os.path.dirname(target))
    try:
        with os.fdopen(fd, "w") as handle:
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
