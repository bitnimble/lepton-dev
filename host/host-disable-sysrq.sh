#!/bin/sh
# Runs as root on the docker host (privileged nsenter). lepton-runner owns /dev/uinput, so it could type
# Alt+SysRq, Ctrl+Alt+Del or power/reboot/suspend keys into the host: turn all of them off. Idempotent.
# SysRq and logind's keys apply now; the Ctrl+Alt+Del mask and burst action apply at the next boot.
# Usage (from this repo): docker run --rm -i --privileged --pid=host alpine:latest \
#     nsenter -t 1 -m -u -i -n -p -- sh -s < host/host-disable-sysrq.sh
set -eu
SYSCTL=/etc/sysctl.d/99-lepton-sysrq.conf
MANAGER=/etc/systemd/system.conf.d/90-lepton-ctrl-alt-del.conf
LOGIND=/etc/systemd/logind.conf.d/90-lepton-ignore-keys.conf

state() {
    echo "$1: kernel.sysrq=$(cat /proc/sys/kernel/sysrq)" \
        "ctrl-alt-del.target=$(systemctl is-enabled ctrl-alt-del.target 2>&1 || true)" \
        "kbrequest.target=$(systemctl is-enabled kbrequest.target 2>&1 || true)" \
        "$(systemctl show -p CtrlAltDelBurstAction)"
}
state before

printf 'kernel.sysrq = 0\n' > "$SYSCTL"
echo 0 > /proc/sys/kernel/sysrq

mkdir -p "${LOGIND%/*}"
{
    echo '[Login]'
    for key in PowerKey RebootKey SuspendKey HibernateKey; do
        echo "Handle$key=ignore"
        echo "Handle${key}LongPress=ignore"
    done
    echo 'HandleLidSwitch=ignore'
    echo 'HandleLidSwitchExternalPower=ignore'
    echo 'HandleLidSwitchDocked=ignore'
} > "$LOGIND"
systemctl reload systemd-logind || echo "logind didn't reload; its settings apply at the next boot"

# --no-reload: a PID 1 daemon-reload can cut running nvidia-runtime containers off from /dev/nvidia*
mkdir -p "${MANAGER%/*}"
printf '[Manager]\nCtrlAltDelBurstAction=none\n' > "$MANAGER"
systemctl mask --no-reload ctrl-alt-del.target
if systemctl cat kbrequest.target >/dev/null 2>&1; then
    systemctl mask --no-reload kbrequest.target
fi

state after
systemd-analyze cat-config sysctl.d | grep -n 'kernel.sysrq' || true
cat "$LOGIND"
