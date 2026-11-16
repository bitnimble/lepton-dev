#!/bin/bash
# Host-side: install Mantis (base + arm64 + xhdpi + en splits) into a running context.
# Usage: install-mantis.sh [ctx]   (default steamlaunch-900002)
set -euo pipefail
C="lepton-${1:-steamlaunch-900002}"
D=/var/lib/containers/lepton/games/mantis
SPLITS=(base.apk split_config.arm64_v8a.apk split_config.xhdpi.apk split_config.en.apk)
docker exec lepton-runner mkdir -p "$D"
docker exec -i lepton-runner sh -c "cat >| $D/mantis.apkm" < "$(cd "$(dirname "$0")/.." && pwd)/data/apks/mantis-3.4.9.1.apkm"
# cmd_real, not pm/adb install: Lepton's cmd wrapper treats every install as the game and moves the game's
# installed APKs, leaving overlay whiteouts that fail the next launch's validation
docker exec lepton-runner bash -c "
set -e
cd $D
unzip -o -q mantis.apkm ${SPLITS[*]}
session=\$(podman exec $C cmd_real package install-create -r | sed -n 's/.*\[\([0-9]*\)\].*/\1/p')
for apk in ${SPLITS[*]}; do
    podman exec -i $C cmd_real package install-write -S \$(stat -c %s \$apk) \$session \$apk - < \$apk
done
podman exec $C cmd_real package install-commit \$session
podman exec $C dumpsys package app.mantispro.gamepad | grep -E 'versionName|primaryCpuAbi'
"
