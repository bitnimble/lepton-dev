#!/bin/bash
# Runs on the host (via nsenter). Idempotent.
set -euo pipefail
STAGE=/tmp/sysbox-install

echo "== binder"
modprobe binder_linux
grep -qx binder_linux /etc/modules-load.d/binder.conf 2>/dev/null || echo binder_linux >| /etc/modules-load.d/binder.conf
grep binder /proc/modules

echo "== sysbox user + subids"
getent passwd sysbox >/dev/null || useradd --system --no-create-home --shell /bin/false sysbox
grep -q '^sysbox:' /etc/subuid || echo 'sysbox:231072:1048576' >> /etc/subuid
grep -q '^sysbox:' /etc/subgid || echo 'sysbox:231072:1048576' >> /etc/subgid
grep '^sysbox:' /etc/subuid /etc/subgid

echo "== sysctl (only values below sysbox minimums)"
printf '%s\n' \
    'fs.inotify.max_user_instances = 1048576' \
    'fs.inotify.max_queued_events = 1048576' \
    'kernel.keys.maxkeys = 20000' \
    'kernel.keys.maxbytes = 1400000' >| /etc/sysctl.d/99-sysbox.conf
sysctl -p /etc/sysctl.d/99-sysbox.conf

echo "== binaries + units"
install -m 0755 "$STAGE"/usr/bin/sysbox-runc "$STAGE"/usr/bin/sysbox-mgr "$STAGE"/usr/bin/sysbox-fs /usr/bin/
install -m 0644 "$STAGE"/lib/systemd/system/sysbox.service "$STAGE"/lib/systemd/system/sysbox-mgr.service "$STAGE"/lib/systemd/system/sysbox-fs.service /etc/systemd/system/
mkdir -p /var/lib/sysboxfs
systemctl daemon-reload
systemctl enable sysbox.service sysbox-mgr.service sysbox-fs.service
systemctl start sysbox-mgr.service sysbox-fs.service sysbox.service
systemctl is-active sysbox.service sysbox-mgr.service sysbox-fs.service

echo "== docker runtime"
CFG=/etc/docker/daemon.json
if [[ "$(jq '.runtimes | has("sysbox-runc")' "$CFG")" != true ]]; then
    cp -a "$CFG" "$CFG.bak-pre-sysbox"
    jq --indent 4 '.runtimes += {"sysbox-runc": {"path": "/usr/bin/sysbox-runc"}}' "$CFG.bak-pre-sysbox" >| "$CFG.new"
    dockerd --validate --config-file "$CFG.new"
    mv "$CFG.new" "$CFG"
fi
diff "$CFG.bak-pre-sysbox" "$CFG" || true
kill -HUP "$(pidof dockerd)"
sleep 2
docker info --format '{{range $k, $v := .Runtimes}}{{$k}} {{end}}'
docker ps -q | wc -l
