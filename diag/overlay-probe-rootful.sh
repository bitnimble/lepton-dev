#!/bin/bash
# Run inside lepton-runner as root. Rootful podman --rootfs :O, kernel overlay vs fuse-overlayfs.
ROOTFS=/home/dev/stage/compat_tool/images/rootfs
for mode in kernel fuse; do
    mkdir -p /var/lib/containers/probe
    root=$(mktemp -d /var/lib/containers/probe/root.XXXX)
    run=$(mktemp -d /run/probe-run.XXXX)
    opts=(--root="$root" --runroot="$run" --storage-driver=overlay)
    [[ $mode == fuse ]] && opts+=(--storage-opt=overlay.mount_program=/usr/sbin/fuse-overlayfs)
    echo "== $mode"
    podman "${opts[@]}" run --rm --read-only --user 0:0 --pid=private --ipc=private --uts=private \
        --rootfs "$ROOTFS":O /system/bin/toybox sh -c "echo hello from android rootfs \($mode\); id; ls /proc | head -3" 2>&1 | tail -5
    podman "${opts[@]}" system reset -f >/dev/null 2>&1
    rm -rf "$root" "$run"
done
