#!/bin/bash
# (Re)creates the lepton-runner sysbox container. Volumes keep the stage, home and podman storage.
set -euo pipefail
BINDER_MAJOR=$(awk '$2 == "binder" {print $1}' /proc/devices)
[[ -n "$BINDER_MAJOR" ]] || { echo "binder_linux not loaded on host" >&2; exit 1; }
docker rm -f lepton-runner >/dev/null 2>&1 || true
docker run -d --runtime=sysbox-runc --security-opt seccomp=unconfined \
    --name lepton-runner --hostname lepton-runner \
    --device /dev/fuse --device /dev/net/tun --device /dev/dma_heap/system --device /dev/uinput \
    --device-cgroup-rule "c ${BINDER_MAJOR}:* rwm" --device-cgroup-rule "c 13:* rwm" \
    -v /dev/input:/dev/input:ro \
    -v /sys/devices/virtual/input:/run/host-virtual-input:ro \
    -p 3459:3459 \
    -v lepton-runner-home:/home/dev \
    -v lepton-runner-containers:/var/lib/containers \
    lepton-runner:dev
for _ in $(seq 30); do
    state=$(docker exec lepton-runner systemctl is-system-running 2>/dev/null || true)
    [[ "$state" == running || "$state" == degraded ]] && break
    sleep 1
done
# sysbox serves /sys/devices/virtual itself, with empty attrs for virtual input devices (and refuses a docker
# bind there); Lepton's gamepad passthrough reads their name/vendor/product
docker exec lepton-runner mount --bind /run/host-virtual-input /sys/devices/virtual/input
echo "runner: $state (binder major $BINDER_MAJOR)"
