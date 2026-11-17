#!/bin/bash
# Host-side: (re)start a Steam-style launch of an .apk/.apkm in lepton-runner, keeping its profile. Detached.
# Usage: steamlaunch.sh <appid> [file inside runner] [wait-seconds]   (no file: the appid is a Play slot)
# Env: LEPTON_STAGE (default stage), LEPTON_NDK_TRANSLATION_MODE (overrides the game's recorded mode:
#      tiered, light-translate-or-interpret, heavy-optimize, interpret-only), LEPTON_ENV_NDK_TRANSLATION_FLAGS
#      (translator flags, default accurate-sigsegv, "none" for none), LEPTON_PADMAP=0 (skip Padmap),
#      LEPTON_GOOGLE_SIGNIN=true (install the game but open the Play Store for sign-in, keep session alive),
#      LEPTON_PLAY_ONLY=true (Play slot: open the Play Store), LEPTON_LAUNCH_PACKAGE=<pkg> (Play slot: launch
#      and record that package)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
APPID="$1"; GAME="${2:-}"; WAIT="${3:-60}"
CTX="steamlaunch-$APPID"
launch_prepare
bash "$(dirname "$0")/pad.sh" start
launch_clear "$CTX"
docker exec -d -e LEPTON_STAGE="${LEPTON_STAGE:-$W/stage}" -e LEPTON_NDK_TRANSLATION_MODE="${LEPTON_NDK_TRANSLATION_MODE:-}" \
    -e LEPTON_ENV_NDK_TRANSLATION_FLAGS="${LEPTON_ENV_NDK_TRANSLATION_FLAGS:-}" -e LEPTON_PADMAP="${LEPTON_PADMAP:-1}" \
    -e LEPTON_GOOGLE_SIGNIN="${LEPTON_GOOGLE_SIGNIN:-}" \
    -e LEPTON_PLAY_ONLY="${LEPTON_PLAY_ONLY:-}" -e LEPTON_LAUNCH_PACKAGE="${LEPTON_LAUNCH_PACKAGE:-}" \
    "$RUNNER" bash -c "$W/run-steamlaunch-rootful.sh '$APPID' '$GAME' '$WAIT' >| '$W/run/$CTX.driver.log' 2>&1"
echo "launched $CTX"
