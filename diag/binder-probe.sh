#!/bin/bash
# Runs as root inside lepton-runner: can this container open a binderfs node at all?
podman inspect lepton-calculator.apk --format '{{json .HostConfig.DeviceCgroupRules}}' 2>&1
d=$(mktemp -d /run/binderprobe.XXXX)
mount -t binder binder "$d" && echo "binderfs mounted"
ls -la "$d"
python3 -c "
import os, sys
try:
    fd = os.open('$d/binder-control', os.O_RDWR); print('open binder-control ok'); os.close(fd)
except OSError as e: print('open binder-control failed:', e)
"
umount "$d"; rmdir "$d"
grep -E "^(c|b|a) " /sys/fs/cgroup/devices.list 2>/dev/null | head -3 || echo "no v1 devices.list (cgroup v2: eBPF device filter)"
