#!/bin/bash
# Runs as root inside lepton-runner: packages the installable Lepton + Padmap bundle (the GApps + NDK stage and
# the patched release files) with lepton-customize. Output: $W/deck-dist/lepton-x86_64-<id>.*
# The packager keeps only Lepton's own files, so the add-on reaches the Deck through deck/install.sh instead.
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
step() { printf '%(%T)T == %s\n' -1 "$*"; }

[[ -z "$(podman ps -q --filter label=lepton=true)" ]] || { echo "stop running Lepton sessions first" >&2; exit 1; }
for path in "$STAGE" "$BAKE" "$PREBAKED"; do
    [[ ! -e "$path" ]] || { echo "already exists: $path" >&2; exit 1; }
done

step "copying the gapps stage"
as_dev cp -a "$WORK/gapps-stage" "$STAGE"
T="$STAGE/compat_tool"
as_dev bash "$W/patches/apply.sh" "$T"

step "sysbake"
bash "$W/sysbake-rootful.sh" "$STAGE" "$BAKE"
mkdir "$PREBAKED"
mv "$BAKE/compat_tool/sysbake" "$BAKE/compat_tool/sysbake.xattrs" "$PREBAKED/"
rm -rf "$BAKE"
chown -R dev:dev "$PREBAKED"
unreadable="$(find "$PREBAKED" ! -perm -u+r | head -n 5 || true)"
[[ -z "$unreadable" ]] || { echo "sysbake has owner-unreadable entries, e.g.:" >&2; echo "$unreadable" >&2; exit 1; }

step "validating and recording the sysbake"
as_dev python3 "$W/deck-record-sysbake.py" "$STAGE" "$PREBAKED"
install -d -o dev -g dev "$OUT"
step "packaging"
as_dev "$T/tools/lepton-customize" package --execute --stage-dir "$STAGE" --output-dir "$OUT" \
    --bundle-id "$ID" --tool-id lepton_padmap --tool-name "Lepton + Padmap (GApps, ARM64) - $ID"
rm -rf "$STAGE" "$PREBAKED"
step "done"
ls -la "$OUT"/lepton-x86_64-"$ID".*
