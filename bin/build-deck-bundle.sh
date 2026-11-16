#!/bin/bash
# Host-side: builds the Lepton + Mantis Steam Deck bundle in lepton-runner and assembles the folder to copy to
# the Deck: data/deck-dist/<id>/ (bundle, checksum, Lepton's installer, deck/install.sh, deck/README.md).
# Usage: build-deck-bundle.sh [bundle-id]   (default mantis-<UTC date>-<time>)
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
ID="${1:-mantis-$(date -u +%Y%m%d-%H%M)}"
OUT="$R/data/deck-dist/$ID"
[[ ! -e "$OUT" ]] || { echo "already built: $OUT" >&2; exit 1; }

bash "$R/mantis-buddy/host/build.sh" >/dev/null
bash "$R/bin/push-inputs.sh" >/dev/null
bash "$R/bin/push.sh" >/dev/null
docker exec lepton-runner bash "$W/build-deck-bundle.sh" "$ID"

mkdir -p "$OUT"
for suffix in .tar.gz .tar.gz.sha256 .install.sh; do
    docker cp "lepton-runner:$W/deck-dist/lepton-x86_64-$ID$suffix" "$OUT/"
done
docker exec lepton-runner sh -c "rm -f $W/deck-dist/lepton-x86_64-$ID.*"
install -m 755 "$R/deck/install.sh" "$R/deck/Install-Lepton-Mantis.desktop" "$OUT/"
install -m 644 "$R/deck/README.md" "$OUT/"
(cd "$OUT" && sha256sum -c "lepton-x86_64-$ID.tar.gz.sha256")
du -sh "$OUT"
echo "Copy $OUT to the Deck's ~/Downloads/lepton-mantis/ (see deck/README.md)."
