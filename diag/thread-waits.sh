#!/bin/bash
# Host-side: per-thread state, wait channel and current syscall for an Android process in a context.
# Usage: thread-waits.sh <ctx> <pid> [comm-regex]
CTX="$1"; PID="$2"; RE="${3:-.}"
docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/sh -c "
for t in /proc/$PID/task/*; do
    c=\$(cat \$t/comm)
    echo \"\$c\" | grep -qE '$RE' || continue
    echo \"\${t##*/} \$c state=\$(cut -d' ' -f3 \$t/stat) wchan=\$(cat \$t/wchan) syscall=\$(cut -d' ' -f1 \$t/syscall)\"
done"
