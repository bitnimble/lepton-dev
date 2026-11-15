#!/bin/bash
# Run inside lepton-runner as dev. Compares podman --rootfs :O with fuse-overlayfs vs kernel overlay.
ROOTFS=/home/dev/stage/compat_tool/images/rootfs
for mode in kernel fuse; do
    root=$(mktemp -d /home/dev/probe-root.XXXX)
    run=$(mktemp -d /tmp/probe-run.XXXX)
    opts=(--root="$root" --runroot="$run" --storage-driver=overlay)
    [[ $mode == fuse ]] && opts+=(--storage-opt=overlay.mount_program=/usr/sbin/fuse-overlayfs)
    echo "== $mode"
    podman "${opts[@]}" run --rm --read-only --userns=keep-id:uid=0,gid=0 --user 0:0 \
        --rootfs "$ROOTFS":O /system/bin/toybox echo "hello from android rootfs ($mode)" 2>&1 | tail -3
    podman "${opts[@]}" unshare rm -rf "$root"
    rm -rf "$run"
done
