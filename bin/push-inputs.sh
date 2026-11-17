#!/bin/bash
# Streams large inputs into the runner volume (docker cp is unreliable under sysbox).
set -euo pipefail
shopt -s nullglob
R="$(cd "$(dirname "$0")/.." && pwd)/data"
D=/var/lib/containers/lepton/inputs
docker exec lepton-runner mkdir -p "$D"
inputs=("$R"/google/x86_64-*.zip
        "$R"/release/lepton-x86_64-*.tar.gz "$R"/release/lepton-x86_64-*.tar.gz.sha256 "$R"/release/lepton-x86_64-*.tar.gz.sha256.sig
        "$R"/apks/*.apk)
for f in "${inputs[@]}"; do
    name=$(basename "$f")
    docker exec lepton-runner test -s "$D/$name" && continue
    docker exec -i lepton-runner sh -c "cat >| '$D/$name.part' && mv '$D/$name.part' '$D/$name'" < "$f"
done
docker exec lepton-runner sh -c "cd $D && ls -la && sha256sum --ignore-missing -c lepton-x86_64-*.tar.gz.sha256"
