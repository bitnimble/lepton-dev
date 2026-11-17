#!/bin/bash
# Host-side: drives the runner's virtual pad (runner/vpad.c). Start it before a launch so Lepton passes it through.
# Usage: pad.sh start | stop
#        pad.sh press <a|b|x|y|lb|rb|back|start|guide|ls|rs|up|down|left|right> [ms]
#        pad.sh stick <l|r> <x> <y>        (-32768..32767)
#        pad.sh trigger <l|r> <0..255>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
send() { runner_exec sh -c "printf '%s\n' '$*' >> $W/run/vpad.fifo"; }

case "$1" in
start)
    runner_exec systemctl is-active -q lepton-vpad ||
        runner_exec systemd-run -q --collect --unit lepton-vpad /bin/bash "$W/vpad.sh"
    ;;
stop) runner_exec systemctl stop lepton-vpad ;;
press)
    case "$2" in
    up) hat="abs 0x11 -1" ;; down) hat="abs 0x11 1" ;; left) hat="abs 0x10 -1" ;; right) hat="abs 0x10 1" ;;
    *)
        declare -A btn=([a]=0x130 [b]=0x131 [x]=0x133 [y]=0x134 [lb]=0x136 [rb]=0x137 [back]=0x13a
            [start]=0x13b [guide]=0x13c [ls]=0x13d [rs]=0x13e)
        code="${btn[$2]:?unknown button $2}"
        ;;
    esac
    if [[ -n "${hat:-}" ]]; then send "$hat"; else send "key $code 1"; fi
    ms="${3:-150}"
    sleep "$((ms / 1000)).$(printf %03d $((ms % 1000)))"
    if [[ -n "${hat:-}" ]]; then send "${hat% *} 0"; else send "key $code 0"; fi
    ;;
stick)
    [[ "$2" == l ]] && axes=(0 1) || axes=(3 4)
    send "abs ${axes[0]} $3"
    send "abs ${axes[1]} $4"
    ;;
trigger) send "abs $([[ "$2" == l ]] && echo 2 || echo 5) $3" ;;
*) echo "unknown command $1" >&2; exit 2 ;;
esac
