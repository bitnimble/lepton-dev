#!/bin/bash
# Host-side: per-thread CPU ticks (100/s) over an interval for an Android process in a context.
# Usage: thread-cpu.sh <ctx> <pid> [seconds]
CTX="$1"; PID="$2"; S="${3:-5}"
docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/sh -c "
snap() { for t in /proc/$PID/task/*; do echo \"\${t##*/} \$(cut -d' ' -f14 \$t/stat) \$(cat \$t/comm | tr ' ' _)\"; done; }
snap > /data/local/tmp/cpu.a; sleep $S; snap > /data/local/tmp/cpu.b
while read tid t name; do
    a=\$(grep \"^\$tid \" /data/local/tmp/cpu.a | cut -d' ' -f2)
    echo \"\$(( t - \${a:-0} )) \$tid \$name\"
done < /data/local/tmp/cpu.b | sort -rn | head -10"
