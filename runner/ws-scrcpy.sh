#!/bin/bash
# Runs as root inside lepton-runner (ws-scrcpy.service): serves ws-scrcpy on :3459 and keeps adb
# connected to every running Lepton session.
W=/var/lib/containers/lepton
source "$W/lepton-env.sh"
adb start-server
while sleep 5; do
    for addr in $("$LEPTON" ps 2>/dev/null | grep -oE '\(([0-9.]+), adb on ([0-9]+)' | sed -E 's/\(([0-9.]+), adb on ([0-9]+)/\1:\2/'); do
        devices=$(adb devices)
        # adb auto-detects Lepton's localhost port forward as an emulator; a second serial for the
        # same device makes ws-scrcpy start two scrcpy-servers that fight over one port
        if grep -q "^emulator-$((${addr#*:} - 1))[[:space:]]device" <<< "$devices"; then
            grep -q "^$addr[[:space:]]" <<< "$devices" && adb disconnect "$addr" >/dev/null
            continue
        fi
        grep -q "^$addr[[:space:]]device" <<< "$devices" || adb connect "$addr" >/dev/null
    done
done &
cd "$W/ws-scrcpy/dist"
WS_SCRCPY_CONFIG="$W/ws-scrcpy.yaml" exec node index.js
