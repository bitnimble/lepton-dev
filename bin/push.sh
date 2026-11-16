#!/bin/bash
# Copies runner scripts, the patched launcher library and the Lepton + Padmap add-on into lepton-runner
# (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
put() { docker exec -i lepton-runner sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }
put "$R/runner/lepton-env.sh" "$W/lepton-env.sh"
put "$R/runner/pipewire-null-sink.conf" /etc/pipewire/pipewire.conf.d/lepton-null-sink.conf
put "$R/runner/ws-scrcpy.yaml" "$W/ws-scrcpy.yaml"
put "$R/runner/ws-scrcpy-lepton.patch" "$W/ws-scrcpy-lepton.patch"
put "$R/runner/vpad.c" "$W/vpad.c"
put "$R/runner/deck-record-sysbake.py" "$W/deck-record-sysbake.py"
put "$R/patches/lepton-x86_64-entry" "$W/patches/lepton-x86_64-entry" 755
put "$R/patches/c2-input-surface.patch" "$W/patches/c2-input-surface.patch"
for script in setup-rootful run-apk-rootful run-steamlaunch-rootful sysbake-rootful ndk-stage gapps-stage watch \
    ws-scrcpy ws-scrcpy-setup vpad build-deck-bundle; do
    put "$R/runner/$script.sh" "$W/$script.sh" 755
done
A="$W/addon"
tar -C "$R/addon" -cf - . | docker exec -i lepton-runner sh -c "rm -rf '$A' && mkdir -p '$A' && tar -C '$A' -xf -"
for stage in stage ndk gapps; do
    T="$W/$stage/compat_tool"
    docker exec lepton-runner test -d "$T/liblepton" || continue
    for lib in liblepton properties; do
        put "$R/patches/$lib.sh" "$T/liblepton/$lib.sh"
    done
    put "$R/patches/lepton-x86_64-entry" "$T/lepton-x86_64-entry" 755
    docker exec lepton-runner sh -c "rm -rf '$T/lepton-padmap' && cp -a '$A' '$T/lepton-padmap'"
done
echo pushed
