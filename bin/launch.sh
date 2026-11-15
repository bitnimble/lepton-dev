#!/bin/bash
# Host-side: fresh-profile launch of an APK in lepton-runner, detached. Poll with status.sh.
# Usage: launch.sh <apk path inside runner> [wait-seconds]
set -euo pipefail
APK="$1"; WAIT="${2:-30}"
CTX="$(basename "$APK" | sed 's/[^a-zA-Z0-9_.-]/_/g')"
bash "$(dirname "$0")/push.sh" >/dev/null
docker exec lepton-runner bash /var/lib/containers/lepton/setup-rootful.sh >/dev/null
docker exec lepton-runner bash -c "podman rm -f 'lepton-$CTX' >/dev/null 2>&1; rm -rf '/var/lib/containers/lepton/home/.local/share/lepton/contexts/$CTX'; rm -f '/var/lib/containers/lepton/run/$CTX.log' '/var/lib/containers/lepton/run/$CTX.png'"
docker exec -d -e LEPTON_STAGE="${LEPTON_STAGE:-/var/lib/containers/lepton/stage}" lepton-runner bash -c "/var/lib/containers/lepton/run-apk-rootful.sh '$APK' '$WAIT' >| '/var/lib/containers/lepton/run/$CTX.driver.log' 2>&1"
echo "launched $CTX"
