#!/bin/bash
# Host-side: install Mantis (base + arm64 + xhdpi + en splits) into a running Lepton context via its adbd.
# Usage: install-mantis.sh <container-ip>
set -euo pipefail
IP="${1:-172.17.0.2}"
D=/var/lib/containers/lepton/games/mantis
docker exec lepton-runner mkdir -p "$D"
docker exec -i lepton-runner sh -c "cat >| $D/mantis.apkm" < "$(cd "$(dirname "$0")/.." && pwd)/data/apks/mantis-3.4.9.1.apkm"
docker exec lepton-runner bash -c "
set -e
cd $D
unzip -o -q mantis.apkm base.apk split_config.arm64_v8a.apk split_config.xhdpi.apk split_config.en.apk
adb connect $IP:5555 >/dev/null
adb -s $IP:5555 install-multiple -r base.apk split_config.arm64_v8a.apk split_config.xhdpi.apk split_config.en.apk
adb -s $IP:5555 shell dumpsys package app.mantispro.gamepad | grep -E 'versionName|primaryCpuAbi'
"
