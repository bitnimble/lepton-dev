#!/bin/bash
# Host-side: sample a process's TCP/UDP sockets (remote addr:port, state) every S seconds, N times.
# Usage: sockets.sh <ctx> <package> [count] [seconds]
CTX="$1"; PKG="$2"; N="${3:-10}"; S="${4:-2}"
docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/sh -c "
P=\$(pidof $PKG)
for i in \$(seq $N); do
    echo \"--- \$(date +%T)\"
    for f in tcp tcp6 udp udp6; do
        tail -n +2 /proc/\$P/net/\$f | while read -r _ l r st _; do
            echo \"\$f \$r \$st\"
        done
    done | sort | uniq -c | grep -v ' 00000000000000000000000000000000:0000 \| 00000000:0000 0A'
    sleep $S
done"
