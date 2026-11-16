#!/bin/bash
# Host-side: runs the Lepton + Padmap add-on CLI inside lepton-runner, from the stage in LEPTON_STAGE.
# Usage: lepton-padmap.sh install|edit [ctx] | report    (ctx defaults to steamlaunch-900002)
set -euo pipefail
W=/var/lib/containers/lepton
CLI="${LEPTON_STAGE:-$W/gapps}/compat_tool/lepton-padmap/lepton-padmap"
case "$1" in
install | edit) docker exec -e HOME="$W/home" lepton-runner "$CLI" "$1" "${2:-steamlaunch-900002}" ;;
*) docker exec -e HOME="$W/home" lepton-runner "$CLI" "$@" ;;
esac
