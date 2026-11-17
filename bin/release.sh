#!/bin/bash
# Host-side: builds the Game Manager, Padmap's APK and the NDK compatibility shim from HEAD (which must be pushed),
# publishes them as GitHub release artifacts-<commit> and pins it in deck/artifacts.env; commit and push that.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
git diff --quiet HEAD -- manager patches/ndk_auxv.c || { echo "Commit manager/ and patches/ndk_auxv.c first." >&2; exit 1; }
git fetch -q origin
[[ -n "$(git branch -r --contains HEAD)" ]] || { echo "Push HEAD first: the release is tagged on it." >&2; exit 1; }
COMMIT="$(git rev-parse HEAD)"
TAG="artifacts-${COMMIT:0:12}"

bash bin/build-manager.sh
bash bin/build-ndk-shim.sh
bash bin/update-padmap.sh
git diff --quiet HEAD -- addon/padmap ':(exclude)addon/padmap/padmap.apk' ||
    { echo "Padmap moved on from addon/padmap/VERSION: commit the vendored update, push, release again." >&2; exit 1; }

ASSETS=(deck/lepton-manager addon/padmap/padmap.apk patches/liblepton_ndk_auxv.so)
gh release create "$TAG" "${ASSETS[@]}" --target "$COMMIT" --title "Built files for ${COMMIT:0:12}" \
    --notes "Game Manager, Padmap APK and NDK compatibility shim built from $COMMIT; deck/fetch-artifacts.sh installs them."
sha() { sha256sum "$1" | cut -d' ' -f1; }
cat >| deck/artifacts.env <<EOF
ARTIFACTS_URL=https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/download/$TAG
LEPTON_MANAGER_SHA256=$(sha deck/lepton-manager)
PADMAP_APK_SHA256=$(sha addon/padmap/padmap.apk)
NDK_AUXV_SHA256=$(sha patches/liblepton_ndk_auxv.so)
EOF
echo "Released $TAG; commit and push deck/artifacts.env."
