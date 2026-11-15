#!/bin/bash
# Host-side: screenshot a running context to data/screens/<name>.png
# Usage: shot.sh <ctx> <name>
CTX="$1"; NAME="$2"
OUT="$(cd "$(dirname "$0")/.." && pwd)/data/screens/$NAME.png"
mkdir -p "$(dirname "$OUT")"
docker exec lepton-runner bash -c "podman exec lepton-$CTX /system/bin/screencap -p /data/local/tmp/shot.png && podman exec lepton-$CTX /system/bin/cat /data/local/tmp/shot.png" >| "$OUT"
file "$OUT"
