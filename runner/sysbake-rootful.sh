#!/bin/bash
# Runs as root inside lepton-runner: root-owned copy of a customized stage, then a fresh sysbake via
# Lepton's own `sysbake` verb (the bundled isolated helper is rootless-only).
# Usage: sysbake-rootful.sh <customized stage dir> <output stage dir>
set -euo pipefail
SRC="$1"; DST="$2"
export LEPTON_STAGE="$DST"
source /var/lib/containers/lepton/lepton-env.sh

if [[ ! -d "$DST" ]]; then
    rsync -a --exclude='.lepton-*' "$SRC/" "$DST/"
    chown -R 0:0 "$DST"
    install -m 0644 /var/lib/containers/lepton/stage/compat_tool/liblepton/liblepton.sh \
        "$DST/compat_tool/liblepton/liblepton.sh"
fi
rm -rf "$DST/compat_tool/sysbake" "$DST/compat_tool/sysbake.xattrs"

ensure_display
ensure_cgroup sysbake
cd "$DST/compat_tool"
LEPTON_ALLOW_LOCAL_SYSBAKE=1 timeout 1500 ./lepton sysbake
getfattr -R -d -m '^user\.' sysbake >| sysbake.xattrs
[[ -f sysbake/system/packages.xml ]] && echo "SYSBAKE-DONE: $(du -sh sysbake | cut -f1)"
