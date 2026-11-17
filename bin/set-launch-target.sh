#!/bin/bash
# Host-side: choose which installed package a Play-installed profile launches.
# The profile must be running (query its package manager); run this right after
# installing the game in install-game.sh, before you quit it.
# Usage:
#   set-launch-target.sh <appid> --list       list installed (third-party) packages, newest first
#   set-launch-target.sh <appid> --newest      target the most-recently-installed package
#   set-launch-target.sh <appid> <package>     target a specific package
set -euo pipefail
source "$(dirname "$0")/lib.sh"
APPID="${1:?usage: set-launch-target.sh <appid> --list|--newest|<package>}"
CHOICE="${2:?usage: set-launch-target.sh <appid> --list|--newest|<package>}"
CTX="steamlaunch-$APPID"
TARGET="$W/steam/compatdata/$APPID/lepton-launch-package"

# Third-party packages in the running profile, newest install first (excludes the Padmap overlay).
# firstInstallTime holds "YYYY-MM-DD HH:MM:SS" (a space), so sort on a |-delimited key then drop it.
list_packages() {
    runner_exec podman exec "lepton-$CTX" /system/bin/sh -c \
        'for p in $(pm list packages -3 | sed s/package://); do
             [ "$p" = app.padmap ] && continue
             t=$(dumpsys package "$p" | sed -n "s/.*firstInstallTime=//p" | head -1)
             echo "$t|$p"
         done | sort -r | sed "s/.*|//"'
}

set_target() { runner_exec sh -c "printf %s '$1' >| '$TARGET'"; echo "launch target for $APPID = $1"; }

case "$CHOICE" in
--list) list_packages ;;
--newest)
    pkg="$(list_packages | head -1)"
    [[ -n "$pkg" ]] || { echo "no third-party package in profile $APPID (is it running, game installed?)" >&2; exit 1; }
    set_target "$pkg" ;;
*) set_target "$CHOICE" ;;
esac
