#!/bin/bash
# Runs as root inside lepton-runner: simulates a Steam launch of an .apk/.apkm (needed for .apkm bundles),
# waits for boot, screenshots after WAIT seconds. Leaves the session running.
# Usage: run-steamlaunch-rootful.sh <appid> /path/to/game.apkm [wait-seconds]
set -euo pipefail
source /var/lib/containers/lepton/lepton-env.sh
APPID="$1"; GAME="$2"; WAIT="${3:-60}"
CTX="steamlaunch-$APPID"

export SteamAppId="$APPID"
export STEAM_COMPAT_INSTALL_PATH="$(dirname "$GAME")"
export STEAM_COMPAT_DATA_PATH="$W/steam/compatdata/$APPID"
export STEAM_COMPAT_SHADER_PATH="$W/steam/shadercache/$APPID"
# Steam includes the library root holding compatdata/; /data/media/0 links into it
export STEAM_COMPAT_LIBRARY_PATHS="$STEAM_COMPAT_INSTALL_PATH:$W/steam"
mkdir -p "$STEAM_COMPAT_DATA_PATH" "$STEAM_COMPAT_SHADER_PATH"

ensure_display
ensure_cgroup "$CTX"

LOG="$W/run/$CTX.log"
# entry, not $LEPTON: the add-on's session hook runs from it, as on a Deck
"$STAGE/compat_tool/lepton-x86_64-entry" waitforexitandrun -- "$GAME" >| "$LOG" 2>&1 &
LPID=$!

for _ in $(seq 900); do
    grep -q "Boot complete!" "$LOG" && break
    kill -0 "$LPID" 2>/dev/null || { echo "launcher exited early"; tail -40 "$LOG"; exit 1; }
    sleep 1
done
grep -q "Boot complete!" "$LOG" || { echo "boot timeout"; tail -40 "$LOG"; exit 1; }
echo "booted; waiting ${WAIT}s for app"
sleep "$WAIT"

podman exec "lepton-$CTX" /system/bin/screencap -p /data/local/tmp/screen.png
podman cp "lepton-$CTX:/data/local/tmp/screen.png" "$W/run/$CTX.png"
echo "screenshot: $W/run/$CTX.png"
