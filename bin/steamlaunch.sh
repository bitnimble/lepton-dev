#!/bin/bash
# Host-side: (re)start a Steam-style launch of an .apk/.apkm in lepton-runner, keeping its profile. Detached.
# Usage: steamlaunch.sh <appid> <file inside runner> [wait-seconds]
# Env: LEPTON_STAGE (default stage), LEPTON_NDK_TRANSLATION_MODE (overrides the game's recorded mode:
#      tiered, light-translate-or-interpret, heavy-optimize, interpret-only)
set -euo pipefail
APPID="$1"; GAME="$2"; WAIT="${3:-60}"
W=/var/lib/containers/lepton
CTX="steamlaunch-$APPID"
bash "$(dirname "$0")/push.sh" >/dev/null
docker exec lepton-runner bash "$W/setup-rootful.sh" >/dev/null
docker exec lepton-runner bash -c "podman rm -f 'lepton-$CTX' >/dev/null 2>&1; rm -f '$W/run/$CTX.log' '$W/run/$CTX.png'"
docker exec -d -e LEPTON_STAGE="${LEPTON_STAGE:-$W/stage}" -e LEPTON_NDK_TRANSLATION_MODE="${LEPTON_NDK_TRANSLATION_MODE:-}" \
    lepton-runner bash -c "$W/run-steamlaunch-rootful.sh '$APPID' '$GAME' '$WAIT' >| '$W/run/$CTX.driver.log' 2>&1"
echo "launched $CTX"
