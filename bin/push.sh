#!/bin/bash
# Copies runner scripts, the patched launcher library and the Lepton + Padmap add-on into lepton-runner
# (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
source "$R/bin/lib.sh"
put "$R/runner/lepton-env.sh" "$W/lepton-env.sh"
put "$R/runner/pipewire-null-sink.conf" /etc/pipewire/pipewire.conf.d/lepton-null-sink.conf
put "$R/runner/ws-scrcpy.yaml" "$W/ws-scrcpy.yaml"
put "$R/runner/ws-scrcpy-lepton.patch" "$W/ws-scrcpy-lepton.patch"
put "$R/runner/vpad.c" "$W/vpad.c"
put "$R/runner/deck-record-sysbake.py" "$W/deck-record-sysbake.py"
for script in setup-rootful run-apk-rootful run-steamlaunch-rootful sysbake-rootful ndk-stage gapps-stage watch \
    ws-scrcpy ws-scrcpy-setup vpad build-deck-bundle; do
    put "$R/runner/$script.sh" "$W/$script.sh" 755
done
for dir in addon patches; do
    tar -C "$R/$dir" -cf - . | docker exec -i lepton-runner sh -c "rm -rf '$W/$dir' && mkdir -p '$W/$dir' && tar -C '$W/$dir' -xf -"
done
for stage in stage ndk gapps; do
    T="$W/$stage/compat_tool"
    docker exec lepton-runner test -d "$T/liblepton" || continue
    runner_exec bash "$W/patches/apply.sh" "$T"
    runner_exec sh -c "rm -rf '$T/lepton-padmap' && cp -a '$W/addon' '$T/lepton-padmap'"
done
echo pushed
