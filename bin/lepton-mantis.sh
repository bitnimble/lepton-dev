#!/bin/bash
# Host-side: runs the Lepton + Mantis add-on CLI inside lepton-runner, from the stage in LEPTON_STAGE.
# Usage: lepton-mantis.sh install|buddy [ctx] | report    (ctx defaults to steamlaunch-900002)
set -euo pipefail
W=/var/lib/containers/lepton
CLI="${LEPTON_STAGE:-$W/gapps}/compat_tool/lepton-mantis/lepton-mantis"
case "$1" in
install | buddy) docker exec lepton-runner "$CLI" "$1" "${2:-steamlaunch-900002}" ;;
*) docker exec -e HOME="$W/home" lepton-runner "$CLI" "$@" ;;
esac
