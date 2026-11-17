#!/bin/bash
# Host-side: runs the Lepton + Padmap add-on CLI inside lepton-runner, from the stage in LEPTON_STAGE.
# Usage: lepton-padmap.sh install|edit [ctx] | report    (ctx defaults to the sole running lepton game)
set -euo pipefail
W=/var/lib/containers/lepton
CLI="${LEPTON_STAGE:-$W/gapps}/compat_tool/lepton-padmap/lepton-padmap"

running_ctx() {
    local names
    mapfile -t names < <(docker exec lepton-runner podman ps --filter label=lepton=true --format '{{.Names}}')
    [[ ${#names[@]} -eq 1 ]] || { echo "specify a context (running: ${names[*]:-none})" >&2; return 1; }
    echo "${names[0]#lepton-}"
}

case "$1" in
install | edit) docker exec -e HOME="$W/home" lepton-runner "$CLI" "$1" "${2:-$(running_ctx)}" ;;
*) docker exec -e HOME="$W/home" lepton-runner "$CLI" "$@" ;;
esac
