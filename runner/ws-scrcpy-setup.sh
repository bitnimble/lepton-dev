#!/bin/bash
# Runs as root inside lepton-runner: builds ws-scrcpy (browser scrcpy client) with ws-scrcpy-lepton.patch
# into $W/ws-scrcpy/dist.
set -euo pipefail
W=/var/lib/containers/lepton
REV=cd6cea6
D="$W/ws-scrcpy"
if [[ ! -d "$D/.git" ]]; then
    rm -rf "$D"
    git clone -q https://github.com/NetrisTV/ws-scrcpy "$D"
fi
git -C "$D" checkout -q -f "$REV"
git -C "$D" clean -fdq src
git -C "$D" apply "$W/ws-scrcpy-lepton.patch"
cd "$D"
npm ci --omit=optional --no-audit --no-fund
npm run dist
cd dist
npm install --omit=dev --omit=optional --no-audit --no-fund
echo "built $D/dist"
