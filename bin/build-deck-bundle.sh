#!/bin/bash
# Host-side: builds the Lepton + Padmap Steam Deck bundle in lepton-runner into data/deck-dist/<id>/
# (bundle, checksum, Lepton's installer), for the Deck checkout's bundle/.
# Usage: build-deck-bundle.sh [bundle-id]   (default padmap-<UTC date>-<time>)
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
source "$R/bin/lib.sh"
ID="${1:-padmap-$(date -u +%Y%m%d-%H%M)}"
[[ "$ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bundle id must be [A-Za-z0-9._-]: $ID" >&2; exit 1; }
OUT="$R/data/deck-dist/$ID"
[[ ! -e "$OUT" ]] || { echo "already built: $OUT" >&2; exit 1; }

bash "$R/bin/push-inputs.sh" >/dev/null
bash "$R/bin/push.sh" >/dev/null
runner_exec bash "$W/build-deck-bundle.sh" "$ID"

mkdir -p "$OUT"
for suffix in .tar.gz .tar.gz.sha256 .install.sh; do
    pull_file "$W/deck-dist/lepton-x86_64-$ID$suffix" "$OUT/lepton-x86_64-$ID$suffix"
done
runner_exec sh -c "rm -f $W/deck-dist/lepton-x86_64-$ID.*"
(cd "$OUT" && sha256sum -c "lepton-x86_64-$ID.tar.gz.sha256")
echo "Copy to the Deck's checkout (see deck/README.md): scp $OUT/* deck@steamdeck:lepton-dev/bundle/"
