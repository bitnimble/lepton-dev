#!/bin/bash
# Host-side: press-tap (150ms, Unity-friendly) one or more points in a context, then screenshot.
# Usage: tap.sh <ctx> <shot-name> x1 y1 [x2 y2 ...]
CTX="$1"; NAME="$2"; shift 2
while (($# >= 2)); do
    docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/input touchscreen swipe "$1" "$2" "$1" "$2" 150
    sleep 3
    shift 2
done
sleep 2
bash "$(dirname "$0")/shot.sh" "$CTX" "$NAME"
