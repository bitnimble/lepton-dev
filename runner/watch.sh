#!/bin/bash
# Runs inside lepton-runner: every 30s, record app pid + resumed activity and a screenshot for a context.
# Usage: watch.sh <ctx> <package>
CTX="$1"; PKG="$2"
OUT=/var/lib/containers/lepton/run/watch-$CTX
mkdir -p "$OUT"
i=0
while podman container exists "lepton-$CTX"; do
    i=$((i + 1))
    ts=$(date +%H%M%S)
    pid=$(podman exec "lepton-$CTX" /system/bin/pidof "$PKG" 2>/dev/null)
    top=$(podman exec "lepton-$CTX" /system/bin/dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity | sed 's/.*{[^ ]* [^ ]* //; s/ t[0-9]*}//')
    echo "$ts pid=${pid:-none} top=$top" >> "$OUT/watch.log"
    podman exec "lepton-$CTX" /system/bin/screencap -p /data/local/tmp/w.png 2>/dev/null &&
        podman cp "lepton-$CTX:/data/local/tmp/w.png" "$OUT/$(printf %03d $i)-$ts.png" 2>/dev/null
    sleep 30
done
echo "$(date +%H%M%S) container gone" >> "$OUT/watch.log"
