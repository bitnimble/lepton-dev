#!/bin/bash
# Host-side: N screenshots S seconds apart into data/screens/<name>-NN.png.
# Usage: burst.sh <ctx> <name> [count] [seconds]
CTX="$1"; NAME="$2"; N="${3:-8}"; S="${4:-3}"
R="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$R/data/screens"
docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/sh -c \
    "for i in \$(seq -w 1 $N); do screencap -p /data/local/tmp/burst-\$i.png; sleep $S; done"
for i in $(seq -w 1 "$N"); do
    docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/cat "/data/local/tmp/burst-$i.png" >| "$R/data/screens/$NAME-$i.png"
done
ls "$R/data/screens/$NAME-"*
