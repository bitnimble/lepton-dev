#!/bin/bash
# Runs as root inside lepton-runner: boots Lepton with an APK, waits, screenshots.
# Usage: run-apk-rootful.sh /path/to/app.apk [seconds-before-screenshot]
set -euo pipefail
source /var/lib/containers/lepton/lepton-env.sh
APK="$1"
WAIT="${2:-30}"
CTX="$(basename "$APK" | sed 's/[^a-zA-Z0-9_.-]/_/g')"

ensure_display
ensure_cgroup "$CTX"

cd "$W/run"
LOG="$W/run/$CTX.log"
"$LEPTON" start "$APK" >| "$LOG" 2>&1 &
LPID=$!
echo "$LPID" >| "$W/run/$CTX.pid"

wait_boot "$LOG" "$LPID" 600 || exit 1
echo "booted; waiting ${WAIT}s for app"
sleep "$WAIT"

screencap_ctx "$CTX" "$W/run/$CTX.png"
podman exec "lepton-$CTX" /system/bin/sh -c 'dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -3' || true
echo "screenshot: $W/run/$CTX.png"
