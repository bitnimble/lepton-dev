#!/bin/bash
# Runs as root inside lepton-runner. Lays out a root-owned Lepton stage on the
# /var/lib/containers volume (overlay upperdirs can't live on the container's own overlay root).
set -euo pipefail
W=/var/lib/containers/lepton
mkdir -p "$W"

if [[ ! -f "$W/stage/compat_tool/lepton" ]]; then
    rsync -a --exclude='.jni-smoke-work.*' /home/dev/stage/ "$W/stage/"
    chown -R 0:0 "$W/stage"
fi

mkdir -p /etc/containers
printf '%s\n' '[containers]' 'default_sysctls = []' '[engine]' 'cgroup_manager = "cgroupfs"' \
    >| /etc/containers/containers.conf

mkdir -p "$W/home/.steam/steam/logs" "$W/home/.local/share/Steam/config" "$W/run"
touch "$W/home/.steam/steam.pipe"
echo "stage ready: $(du -sh "$W/stage" | cut -f1)"
