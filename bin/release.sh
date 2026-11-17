#!/bin/bash
# Host-side: builds the Game Manager, Padmap's APK, the Lepton helper APK and the NDK compatibility shim from HEAD,
# publishes them as GitHub release build-<UTC time> and pins it in deck/artifacts.env: commit that and push both
# together.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
git diff --quiet HEAD -- manager helper patches/ndk_auxv.c ||
    { echo "Commit manager/, helper/ and patches/ndk_auxv.c first." >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
TAG="build-$(date -u +%Y%m%d-%H%M%S)"

bash bin/build-manager.sh
bash bin/build-ndk-shim.sh
bash bin/build-helper.sh
bash bin/update-padmap.sh
git diff --quiet HEAD -- addon/padmap ':(exclude)addon/padmap/padmap.apk' ||
    { echo "Padmap moved on from addon/padmap/VERSION: commit the vendored update and release again." >&2; exit 1; }

ASSETS=(deck/lepton-manager addon/padmap/padmap.apk addon/lepton-helper.apk patches/liblepton_ndk_auxv.so)
# The tag goes on GitHub's main (HEAD may not be pushed yet); the notes name the commit the files come from.
gh release create "$TAG" "${ASSETS[@]}" --title "Built files from ${COMMIT:0:12}" \
    --notes "Game Manager, Padmap APK, Lepton helper APK and NDK compatibility shim built from $COMMIT; deck/fetch-artifacts.sh installs them."
sha() { sha256sum "$1" | cut -d' ' -f1; }
cat >| deck/artifacts.env <<EOF
ARTIFACTS_URL=https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/download/$TAG
LEPTON_MANAGER_SHA256=$(sha deck/lepton-manager)
PADMAP_APK_SHA256=$(sha addon/padmap/padmap.apk)
HELPER_APK_SHA256=$(sha addon/lepton-helper.apk)
NDK_AUXV_SHA256=$(sha patches/liblepton_ndk_auxv.so)
EOF
echo "Released $TAG; commit deck/artifacts.env and push it with the sources it was built from."
