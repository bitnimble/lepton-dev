#!/bin/bash
# Host-side: builds Padmap (PADMAP_DIR, default ../padmap next to this repo) with its Gradle wrapper, running its
# tests, and vendors its APK, start script, README and shared layouts into addon/padmap/, so the add-on (and a
# Deck's git pull) ships them.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
P="${PADMAP_DIR:-$R/../padmap}"
OUT="$R/addon/padmap"
"$P/gradlew" -p "$P" --quiet check :app:assembleRelease
NEW="$OUT.new"
rm -rf "$NEW"
mkdir -p "$NEW/layouts"
cp "$P/app/build/outputs/apk/release/app-release.apk" "$NEW/padmap.apk"
cp "$P/app/src/main/assets/start.sh" "$P/README.md" "$NEW/"
cp "$P"/layouts/*.json "$NEW/layouts/"
DIRTY=""
[[ -z "$(git -C "$P" status --porcelain)" ]] || DIRTY=" (uncommitted changes)"
printf '%s%s\n' "$(git -C "$P" log -1 --format='padmap %h %cs %s')" "$DIRTY" >"$NEW/VERSION"
rm -rf "$OUT"
mv "$NEW" "$OUT"
cat "$OUT/VERSION"
