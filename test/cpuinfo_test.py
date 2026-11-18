import os
import subprocess
import sys
import tempfile

ADDON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addon", "ndk-translation")
sys.path.insert(0, ADDON)
import cpuinfo  # noqa: E402

SHIPPED = (
    "processor\t: 1\n"
    "BogoMIPS\t: 1.00\n"
    "Features\t: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp\n"
    "CPU implementer\t: 0x41\n"
    "CPU architecture: 8\n"
    "CPU variant\t: 0x6\n"
    "CPU part\t: 0x802\n"
    "CPU revision\t: 13\n"
)
BODY = SHIPPED.split("\n", 1)[1]

assert cpuinfo.expanded(SHIPPED, 3) == (
    "processor\t: 0\n" + BODY + "\n" + "processor\t: 1\n" + BODY + "\n" + "processor\t: 2\n" + BODY + "\n"
), "one entry per CPU, numbered from 0, rest of the shipped entry kept"
assert cpuinfo.expanded(SHIPPED + "\nHardware\t: Lepton\n", 2).endswith(
    "processor\t: 1\n" + BODY + "\nHardware\t: Lepton\n"
), "lines after the CPU entry stay once, at the end"

with tempfile.TemporaryDirectory() as directory:
    rootfs, overlay = os.path.join(directory, "rootfs"), os.path.join(directory, "overlay")
    os.makedirs(os.path.join(rootfs, "system/etc"))
    with open(os.path.join(rootfs, cpuinfo.CPUINFO), "w") as handle:
        handle.write(SHIPPED)
    script = os.path.join(ADDON, "cpuinfo.py")
    first = subprocess.run([sys.executable, script, rootfs, overlay], check=True, capture_output=True, text=True)
    assert first.stdout.startswith("wrote "), "first run writes the overlay copy"
    with open(os.path.join(overlay, cpuinfo.CPUINFO)) as handle:
        written = handle.read()
    assert written.count("processor\t:") == len(os.sched_getaffinity(0)), "as many entries as usable host CPUs"
    second = subprocess.run([sys.executable, script, rootfs, overlay], check=True, capture_output=True, text=True)
    assert second.stdout == "", "unchanged overlay copy is left alone"
print("cpuinfo_test: all passed")
