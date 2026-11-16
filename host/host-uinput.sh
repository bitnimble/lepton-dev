#!/bin/sh
# Runs as root on the docker host (privileged nsenter). Loads the uinput kernel module and gives the
# sysbox user namespace's root (host uid 165536 = root in lepton-runner) ownership of /dev/uinput, so
# Lepton can pass it to Android for Mantis's input injection. Mode stays 0600.
# Usage (from this repo): docker run --rm -i --privileged --pid=host alpine:latest \
#     nsenter -t 1 -m -u -i -n -p -- sh -s < host/host-uinput.sh
set -eu
DEV=/dev/uinput
RULE=/etc/udev/rules.d/70-lepton-uinput.rules
LOADCONF=/etc/modules-load.d/lepton-uinput.conf

modprobe uinput
# devtmpfs creates the node on module load; wait briefly if it lags
i=0
while [ ! -c "$DEV" ] && [ $i -lt 20 ]; do i=$((i + 1)); sleep 0.1; done
[ -c "$DEV" ] || { echo "no $DEV after modprobe" >&2; exit 1; }
ls -ln "$DEV"
grep -rl uinput /usr/lib/udev/rules.d /etc/udev/rules.d 2>/dev/null || true

chown 165536 "$DEV"
printf 'uinput\n' > "$LOADCONF"
printf '%s\n' 'SUBSYSTEM=="misc", KERNEL=="uinput", OWNER="165536", MODE="0600"' > "$RULE"
udevadm control --reload || true
ls -ln "$DEV"
cat "$LOADCONF" "$RULE"
