#!/bin/bash
# Runs as root inside lepton-runner (systemd-run unit lepton-vpad): builds and runs the virtual pad, fed from a FIFO.
set -euo pipefail
W=/var/lib/containers/lepton
[[ "$W/vpad" -nt "$W/vpad.c" ]] || gcc -O2 -o "$W/vpad" "$W/vpad.c"
mkdir -p "$W/run"
[[ -p "$W/run/vpad.fifo" ]] || mkfifo -m 600 "$W/run/vpad.fifo"
# read-write open: the pad never sees EOF when a writer closes
exec "$W/vpad" <>"$W/run/vpad.fifo"
