#!/bin/bash
# Host-side: fresh-profile launch of an APK in lepton-runner, detached. Poll with status.sh.
# Usage: launch.sh <apk path inside runner> [wait-seconds]
set -euo pipefail
source "$(dirname "$0")/lib.sh"
APK="$1"; WAIT="${2:-30}"
CTX="$(basename "$APK" | sed 's/[^a-zA-Z0-9_.-]/_/g')"
[[ "$CTX" != . && "$CTX" != .. ]] || { echo "bad APK name: $APK" >&2; exit 2; }
launch_prepare
launch_clear "$CTX"
runner_exec rm -rf "$W/home/.local/share/lepton/contexts/$CTX"
docker exec -d -e LEPTON_STAGE="${LEPTON_STAGE:-$W/stage}" "$RUNNER" bash -c "$W/run-apk-rootful.sh '$APK' '$WAIT' >| '$W/run/$CTX.driver.log' 2>&1"
echo "launched $CTX"
