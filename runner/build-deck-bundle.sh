#!/bin/bash
# Runs as root inside lepton-runner: packages the installable Lepton + Mantis bundle (the GApps + NDK stage,
# the add-on and the patched Steam entry) with lepton-customize. Output: $W/deck-dist/lepton-x86_64-<id>.*
# Usage: build-deck-bundle.sh <bundle-id>
set -euo pipefail
ID="$1"
W=/var/lib/containers/lepton
WORK="$W/work"
STAGE="$WORK/deck-$ID"
BAKE="$WORK/deck-$ID-bake"
PREBAKED="$WORK/deck-$ID-prebaked"
OUT="$W/deck-dist"
as_dev() { runuser -u dev -- "$@"; }

[[ -z "$(podman ps -q --filter label=lepton=true)" ]] || { echo "stop running Lepton sessions first" >&2; exit 1; }
for path in "$STAGE" "$BAKE" "$PREBAKED"; do
    [[ ! -e "$path" ]] || { echo "already exists: $path" >&2; exit 1; }
done

as_dev cp -a "$WORK/gapps-stage" "$STAGE"
T="$STAGE/compat_tool"
install -o dev -g dev -m 755 "$W/patches/lepton-x86_64-entry" "$T/lepton-x86_64-entry"
as_dev git -C "$STAGE" apply "$W/patches/c2-input-surface.patch"
install -d -o dev -g dev "$T/lepton-mantis"
cp -a "$W/addon/." "$T/lepton-mantis/"
cp "$W/inputs/mantis-3.4.9.1.apkm" "$T/lepton-mantis/mantis.apkm"
chown -R dev:dev "$T/lepton-mantis"

bash "$W/sysbake-rootful.sh" "$STAGE" "$BAKE"
mkdir "$PREBAKED"
mv "$BAKE/compat_tool/sysbake" "$BAKE/compat_tool/sysbake.xattrs" "$PREBAKED/"
rm -rf "$BAKE"
chown -R dev:dev "$PREBAKED"
unreadable="$(find "$PREBAKED" ! -perm -u+r | head -n 5)"
[[ -z "$unreadable" ]] || { echo "sysbake has owner-unreadable entries, e.g.:" >&2; echo "$unreadable" >&2; exit 1; }

as_dev python3 "$W/deck-record-sysbake.py" "$STAGE" "$PREBAKED"
install -d -o dev -g dev "$OUT"
as_dev "$T/tools/lepton-customize" package --execute --stage-dir "$STAGE" --output-dir "$OUT" \
    --bundle-id "$ID" --tool-id lepton_mantis --tool-name "Lepton + Mantis (GApps, ARM64) - $ID"
rm -rf "$STAGE" "$PREBAKED"
ls -la "$OUT"/lepton-x86_64-"$ID".*
