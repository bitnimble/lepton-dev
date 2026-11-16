#!/bin/bash
# Host-side: builds Padmap (PADMAP_DIR, default ../padmap next to this repo) and vendors its APK, start script,
# README and shared layouts into addon/padmap/, so the add-on (and a Deck's git pull) ships them.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
P="${PADMAP_DIR:-$R/../padmap}"
OUT="$R/addon/padmap"
bash "$P/build.sh"
NEW="$OUT.new"
rm -rf "$NEW"
mkdir -p "$NEW/layouts"
cp "$P/build/padmap.apk" "$P/assets/start.sh" "$P/README.md" "$NEW/"
cp "$P"/layouts/*.json "$NEW/layouts/"
DIRTY=""
[[ -z "$(git -C "$P" status --porcelain)" ]] || DIRTY=" (uncommitted changes)"
printf '%s%s\n' "$(git -C "$P" log -1 --format='padmap %h %cs %s')" "$DIRTY" >"$NEW/VERSION"
rm -rf "$OUT"
mv "$NEW" "$OUT"
cat "$OUT/VERSION"
