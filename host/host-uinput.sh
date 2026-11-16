#!/bin/sh
# Runs as root on the docker host (privileged nsenter). Loads the uinput kernel module and gives the
# sysbox user namespace's root (host uid 165536 = root in lepton-runner) ownership of /dev/uinput and of the
# event nodes of the virtual pad below, so the runner can create the pad and Lepton can pass it to Android.
# Idempotent.
# Usage (from this repo): docker run --rm -i --privileged --pid=host alpine:latest \
#     nsenter -t 1 -m -u -i -n -p -- sh -s < host/host-uinput.sh
set -eu
DEV=/dev/uinput
RULE=/etc/udev/rules.d/70-lepton-uinput.rules
LOADCONF=/etc/modules-load.d/lepton-uinput.conf

# Event nodes of the runner's Steam-Input-style virtual pad (Valve 28de:11ff). Only uinput-created (virtual)
# devices match; real host inputs keep their owner.
cat > "$RULE.tmp" <<'EOF'
SUBSYSTEM=="misc", KERNEL=="uinput", OWNER="165536", MODE="0600"
SUBSYSTEM=="input", KERNEL=="event*", DEVPATH=="/devices/virtual/input/*", ATTRS{id/vendor}=="28de", ATTRS{id/product}=="11ff", OWNER="165536"
EOF
udevadm verify "$RULE.tmp"
mv "$RULE.tmp" "$RULE"
udevadm control --reload
printf 'uinput\n' > "$LOADCONF"

modprobe uinput
udevadm settle
[ -c "$DEV" ] || { echo "no $DEV after modprobe" >&2; exit 1; }
chown 165536 "$DEV"
ls -ln "$DEV"
cat "$LOADCONF" "$RULE"
