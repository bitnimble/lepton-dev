#!/bin/bash
# Copies the extracted sysbox payload to /tmp/sysbox-install on the host and verifies checksums.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)/data/sysbox/root"
cd "$SRC"
tar -czf ../payload.tgz usr/bin lib/systemd/system
docker run --rm -i --privileged --pid=host alpine:latest \
    nsenter -t 1 -m -u -i -n -p -- sh -c \
    'rm -rf /tmp/sysbox-install && mkdir -p /tmp/sysbox-install && tar -xzf - -C /tmp/sysbox-install && cd /tmp/sysbox-install && sha256sum usr/bin/* lib/systemd/system/*' \
    < ../payload.tgz >| ../host-sums.txt
sha256sum usr/bin/* lib/systemd/system/* >| ../local-sums.txt
diff ../local-sums.txt ../host-sums.txt && echo "payload verified"
