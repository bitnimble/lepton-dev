#!/bin/bash
# Host-side: eth0 rx/tx byte delta over an interval, plus established TCP connections, for a context.
# Usage: net-rate.sh <ctx> [seconds]
CTX="$1"; S="${2:-10}"
docker exec lepton-runner podman exec "lepton-$CTX" /system/bin/sh -c "
bytes() { grep eth0 /proc/net/dev | tr -s ' ' | cut -d' ' -f3,11; }
a=\$(bytes); sleep $S; b=\$(bytes)
echo \"rx/tx before: \$a  after: \$b  (${S}s)\"
echo \"established tcp: \$(grep -c ' 01 ' /proc/net/tcp /proc/net/tcp6 | tr '\n' ' ')\""
