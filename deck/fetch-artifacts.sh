#!/usr/bin/env bash
# Puts this checkout's built files in place from the GitHub release pinned in deck/artifacts.env (published by
# bin/release.sh): the Game Manager, Padmap's APK, the Lepton helper APK and the NDK compatibility shim. Files that already match are kept.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$REPO/deck/artifacts.env"
source "$REPO/deck/download.sh"

get() {  # get ASSET SHA256 PATH MODE
    local file="$REPO/$3"
    if [[ -f "$file" ]] && sha256sum -c --quiet - <<< "$2  $file" >/dev/null 2>&1; then
        return
    fi
    fetch "$ARTIFACTS_URL/$1" "$file.new"
    verify sha256 "$2" "$file.new"
    chmod "$4" "$file.new"
    mv -- "$file.new" "$file"
}

get lepton-manager "$LEPTON_MANAGER_SHA256" deck/lepton-manager 755
get padmap.apk "$PADMAP_APK_SHA256" addon/padmap/padmap.apk 644
get lepton-helper.apk "$HELPER_APK_SHA256" addon/lepton-helper.apk 644
get liblepton_ndk_auxv.so "$NDK_AUXV_SHA256" patches/liblepton_ndk_auxv.so 644
