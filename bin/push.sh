#!/bin/bash
# Copies runner scripts and the patched launcher library into lepton-runner (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
put() { docker exec -i lepton-runner sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }
put "$R/runner/lepton-env.sh" "$W/lepton-env.sh"
put "$R/runner/pipewire-null-sink.conf" /etc/pipewire/pipewire.conf.d/lepton-null-sink.conf
put "$R/runner/ws-scrcpy.yaml" "$W/ws-scrcpy.yaml"
put "$R/runner/ws-scrcpy-lepton.patch" "$W/ws-scrcpy-lepton.patch"
put "$R/runner/vpad.c" "$W/vpad.c"
put "$R/mantis-buddy/start-buddy.sh" "$W/mantis-start-buddy.sh"
for script in setup-rootful run-apk-rootful run-steamlaunch-rootful sysbake-rootful ndk-stage gapps-stage watch \
    ws-scrcpy ws-scrcpy-setup vpad; do
    put "$R/runner/$script.sh" "$W/$script.sh" 755
done
for stage in stage ndk gapps; do
    if docker exec lepton-runner test -d "$W/$stage/compat_tool/liblepton"; then
        for lib in liblepton properties; do
            put "$R/patches/$lib.sh" "$W/$stage/compat_tool/liblepton/$lib.sh" 644
        done
    fi
done
echo pushed
