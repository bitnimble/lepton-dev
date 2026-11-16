#!/bin/bash
# Copies runner scripts, the patched launcher library and the Lepton + Mantis add-on into lepton-runner
# (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
put() { docker exec -i lepton-runner sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }
[[ -f "$R/data/mantis-buddy/host.apk" ]] || bash "$R/mantis-buddy/host/build.sh" >/dev/null
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
for file in entry-hook.sh orient-display.sh start-buddy.sh ndk-mode.py ndk-modes; do
    put "$R/addon/$file" "$A/$file"
done
put "$R/addon/lepton-mantis" "$A/lepton-mantis" 755
put "$R/data/mantis-buddy/host.apk" "$A/mantis-buddy-host.apk"
for stage in stage ndk gapps; do
    T="$W/$stage/compat_tool"
    docker exec lepton-runner test -d "$T/liblepton" || continue
    for lib in liblepton properties; do
        put "$R/patches/$lib.sh" "$T/liblepton/$lib.sh"
    done
    put "$R/patches/lepton-x86_64-entry" "$T/lepton-x86_64-entry" 755
    docker exec lepton-runner sh -c "mkdir -p '$T/lepton-mantis' && cp -a '$A/.' '$T/lepton-mantis/' &&
        cp -u '$W/inputs/mantis-3.4.9.1.apkm' '$T/lepton-mantis/mantis.apkm'"
done
echo pushed
