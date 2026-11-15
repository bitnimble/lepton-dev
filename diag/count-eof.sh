#!/bin/bash
# Counts sysbox-fs EOF warnings before/after one rootless nested proc mount attempt in lepton-runner.
count() {
    docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -i -n -p -- \
        sh -c 'journalctl -u sysbox-fs --since "-10min" --no-pager | grep -c "first-child pid"'
}
before=$(count)
docker exec -u dev lepton-runner sh -c 'unshare -Urmpf --mount-proc true' 2>&1
sleep 2
after=$(count)
echo "EOF warnings before=$before after=$after"
docker run --rm --privileged --pid=host alpine:latest nsenter -t 1 -m -u -i -n -p -- \
    sh -c 'journalctl -u sysbox-fs --since "-20s" --no-pager | grep -v "reap" | tail -15'
