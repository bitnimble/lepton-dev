#!/bin/sh
# Runs as root on the docker host (privileged nsenter). Gives the sysbox user namespace's root
# (host uid 165536 = root in lepton-runner) ownership of the DMA-BUF system heap, which Lepton
# passes to Android for Codec2 buffers. Mode stays 0600.
# Usage (from this repo): docker run --rm -i --privileged --pid=host alpine:latest \
#     nsenter -t 1 -m -u -i -n -p -- sh -s < host/host-dma-heap.sh
set -eu
DEV=/dev/dma_heap/system
RULE=/etc/udev/rules.d/70-lepton-dma-heap.rules
[ -c "$DEV" ] || { echo "missing $DEV" >&2; exit 1; }
ls -ln "$DEV"
grep -rl dma_heap /usr/lib/udev/rules.d /etc/udev/rules.d 2>/dev/null || true
chown 165536 "$DEV"
printf '%s\n' 'SUBSYSTEM=="dma_heap", KERNEL=="system", OWNER="165536", MODE="0600"' > "$RULE"
udevadm control --reload
ls -ln "$DEV"
cat "$RULE"
