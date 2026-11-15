#!/bin/bash
# Copies runner scripts and the patched launcher library into lepton-runner (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
put() { docker exec -i lepton-runner sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }
put "$R/runner/lepton-env.sh" "$W/lepton-env.sh"
for script in setup-rootful run-apk-rootful run-steamlaunch-rootful sysbake-rootful ndk-stage gapps-stage watch; do
    put "$R/runner/$script.sh" "$W/$script.sh" 755
done
for stage in stage ndk gapps; do
    if docker exec lepton-runner test -d "$W/$stage/compat_tool/liblepton"; then
        put "$R/patches/liblepton.sh" "$W/$stage/compat_tool/liblepton/liblepton.sh" 644
    fi
done
echo pushed
