#!/bin/bash
# Host-side: installs the buddy host apk into a running context (when changed) and (re)starts the Mantis buddy.
# Usage: mantis-buddy.sh [ctx]   (default steamlaunch-900002)
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
C="lepton-${1:-steamlaunch-900002}"
APK="$R/data/mantis-buddy/host.apk"
[[ -f "$APK" ]] || bash "$R/mantis-buddy/host/build.sh" >/dev/null
docker exec -i lepton-runner podman exec -i "$C" sh -c 'cat >| /data/local/tmp/mantisbuddy.apk.new' < "$APK"
docker exec lepton-runner podman exec "$C" sh -c '
    cd /data/local/tmp
    if cmp -s mantisbuddy.apk.new mantisbuddy.apk && cmd_real package path lepton.mantisbuddy >/dev/null; then
        rm mantisbuddy.apk.new
    else
        mv mantisbuddy.apk.new mantisbuddy.apk
        # cmd_real, not pm: Lepton wraps cmd with a game post-install hook that hangs intermittently here
        cmd_real package install -r mantisbuddy.apk </dev/null
    fi'
docker exec -i lepton-runner podman exec -i "$C" sh -s < "$R/mantis-buddy/start-buddy.sh"
