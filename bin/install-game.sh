#!/bin/bash
# Host-side: boot a fresh isolated profile into the Play Store so you can sign in
# and install a game. The game installs into this profile's own data (one
# compatdata per appid). After it downloads, point the profile at it:
#   bin/set-launch-target.sh <appid> --newest     (or a specific package)
# then launch it normally with steamlaunch.sh <appid> (no game file needed).
# Usage: install-game.sh <appid> [stage]   (stage defaults to gapps, for Play services)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
APPID="${1:?usage: install-game.sh <appid> [stage]}"
STAGE="${2:-gapps}"
LEPTON_STAGE="$W/$STAGE" LEPTON_PLAY_ONLY=true LEPTON_GOOGLE_SIGNIN=true \
    bash "$(dirname "$0")/steamlaunch.sh" "$APPID" "" "${LEPTON_INSTALL_WAIT:-0}"
echo "Profile $APPID is booting to the Play Store. Sign in, install your game, then:"
echo "  bin/set-launch-target.sh $APPID --newest"
