#!/bin/bash
# Streams large inputs into the runner volume (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)/data"
D=/var/lib/containers/lepton/inputs
docker exec lepton-runner mkdir -p "$D"
for f in google/x86_64-34_r14.zip \
         release/lepton-x86_64-v0.2.0-alpha.tar.gz \
         release/lepton-x86_64-v0.2.0-alpha.tar.gz.sha256 \
         release/lepton-x86_64-v0.2.0-alpha.tar.gz.sha256.sig \
         apks/aaaaxy-arm64.apk apks/calculator-10-foss-release.apk apks/mantis-3.4.9.1.apkm; do
    name=$(basename "$f")
    docker exec lepton-runner test -s "$D/$name" && continue
    docker exec -i lepton-runner sh -c "cat >| '$D/$name'" < "$R/$f"
done
docker exec lepton-runner sh -c "cd $D && ls -la && sha1sum x86_64-34_r14.zip && sha256sum --ignore-missing -c lepton-x86_64-v0.2.0-alpha.tar.gz.sha256"
