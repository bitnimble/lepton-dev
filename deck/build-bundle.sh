#!/usr/bin/env bash
# Builds the Lepton + Padmap bundle on this machine from official downloads, nothing redistributed: Lepton's
# signed release from GitHub and Google's Play system image (ARM translation + Google services) from
# dl.google.com, both pinned in deck/bundle.env. Output: bundle/lepton-x86_64-$BUNDLE_ID.*, for deck/install.sh.
# Needs about 8 GB free; downloads stay in ~/.cache/lepton-padmap/downloads for a rebuild.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$REPO/deck/bundle.env"
source "$REPO/deck/download.sh"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lepton-padmap"
DL="$CACHE/downloads"
WORK="$CACHE/build"
REL="lepton-x86_64-$LEPTON_RELEASE"
GH="https://github.com/pjohno/lepton-x86_64/releases/download/$LEPTON_RELEASE"
ZIP="$DL/${GOOGLE_IMAGE_URL##*/}"
step() { printf '%(%T)T == %s\n' -1 "$*"; }

mkdir -p "$DL"
free_gb="$(df -BG --output=avail "$CACHE" | tail -1 | tr -dc 0-9)"
((free_gb >= 8)) || { echo "Building needs about 8 GB free in $CACHE; there is ${free_gb} GB." >&2; exit 1; }
if [[ -e "$WORK" ]]; then
    podman unshare rm -rf -- "$WORK"
fi
mkdir -p "$WORK/release"
step "downloading Lepton $LEPTON_RELEASE (GitHub) and Google's API 34 Play image (dl.google.com)"
for file in "$REL.tar.gz" "$REL.tar.gz.sha256" "$REL.tar.gz.sha256.sig"; do
    fetch "$GH/$file" "$DL/$file"
done
verify sha256 "$LEPTON_RELEASE_SHA256" "$DL/$REL.tar.gz"
fetch "$GOOGLE_IMAGE_URL" "$ZIP"
verify sha1 "$GOOGLE_IMAGE_SHA1" "$ZIP"

tar -xzf "$DL/$REL.tar.gz" -C "$WORK/release" ./compat_tool/tools ./compat_tool/release-keys
step "Lepton base stage"
"$WORK/release/compat_tool/tools/lepton-customize" --execute --bundle "$DL/$REL.tar.gz" \
    --checksum "$DL/$REL.tar.gz.sha256" --trusted-signers "$WORK/release/compat_tool/release-keys/allowed_signers" \
    --stage-dir "$WORK/base"
step "adding ARM translation and Google services"
"$WORK/base/compat_tool/tools/lepton-customize" inject --execute --stage-dir "$WORK/base" \
    --output-stage "$WORK/stage" --google-zip "$ZIP" --with-ndk --with-gapps
rm -rf -- "$WORK/base" "$WORK/release"
C="$WORK/stage/compat_tool/tools/lepton-customize"

step "first Android boot (sysbake)"
if ! command -v weston >/dev/null; then
    mkdir -p "$WORK/bin"
    ln -s "$REPO/deck/weston-via-gamescope" "$WORK/bin/weston"
    export PATH="$WORK/bin:$PATH"
fi
"$C" sysbake --execute --stage-dir "$WORK/stage" --rendering amd

step "packaging"
mkdir -p "$REPO/bundle"
"$C" package --execute --stage-dir "$WORK/stage" --output-dir "$REPO/bundle" --bundle-id "$BUNDLE_ID" \
    --tool-id lepton_padmap --tool-name "Lepton + Padmap (GApps, ARM64)"
podman unshare rm -rf -- "$WORK"
step "built $REPO/bundle/lepton-x86_64-$BUNDLE_ID.tar.gz"
