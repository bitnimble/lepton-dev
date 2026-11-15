#!/bin/bash
# Runs on the host (via nsenter). Expects the new binary at /tmp/sysbox-fs.new.
set -euo pipefail
NEW_SHA=2e272fcb9d2642a7d14ef2391ef23b05157323d385c4eb0fd15d7955ea5ea83a

echo "== reverse deps (must not include docker/containerd)"
systemctl show -p RequiredBy,BoundBy,ConsistsOf,PartOf sysbox.service sysbox-fs.service sysbox-mgr.service
systemctl list-dependencies --reverse --plain sysbox.service
if systemctl show -p RequiredBy,BoundBy sysbox.service sysbox-fs.service sysbox-mgr.service | grep -Eq 'docker|containerd'; then
    echo "docker/containerd depends on sysbox; aborting" >&2
    exit 1
fi

echo "== verify new binary"
[[ -x /tmp/sysbox-fs.new ]]
echo "$NEW_SHA  /tmp/sysbox-fs.new" | sha256sum -c -
/tmp/sysbox-fs.new --version
echo "== current binary"
/usr/bin/sysbox-fs --version

if [[ ! -e /usr/bin/sysbox-fs.0.7.1 ]]; then
    /usr/bin/sysbox-fs --version | grep -q '0.7.1' || { echo "current sysbox-fs is not 0.7.1; aborting" >&2; exit 1; }
    cp -a /usr/bin/sysbox-fs /usr/bin/sysbox-fs.0.7.1
fi
/usr/bin/sysbox-fs.0.7.1 --version

install -m 0755 /tmp/sysbox-fs.new /usr/bin/sysbox-fs.tmp
mv -f /usr/bin/sysbox-fs.tmp /usr/bin/sysbox-fs

systemctl restart sysbox.service
sleep 2
systemctl is-active sysbox.service sysbox-mgr.service sysbox-fs.service || {
    journalctl -u sysbox-fs -u sysbox-mgr -n 80 --no-pager
    echo "rollback: install -m0755 /usr/bin/sysbox-fs.0.7.1 /usr/bin/sysbox-fs && systemctl restart sysbox.service" >&2
    exit 1
}
/usr/bin/sysbox-fs --version
