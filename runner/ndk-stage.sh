#!/bin/bash
# Runs as root inside lepton-runner: base stage from the release bundle, then NDK-translation inject.
set -euo pipefail
W=/var/lib/containers/lepton
IN=$W/inputs
WORK=$W/work
mkdir -p "$WORK"
C="$W/stage/compat_tool/tools/lepton-customize"
shopt -s nullglob
bundles=("$IN"/lepton-x86_64-*.tar.gz)
[[ ${#bundles[@]} -eq 1 ]] || { echo "expected exactly one release bundle (lepton-x86_64-*.tar.gz) in $IN, found ${#bundles[@]}" >&2; exit 1; }
BUNDLE="${bundles[0]}"

if [[ ! -d "$WORK/base-stage" ]]; then
    "$C" --execute \
        --bundle "$BUNDLE" \
        --checksum "$BUNDLE.sha256" \
        --signature "$BUNDLE.sha256.sig" \
        --trusted-signers "$W/stage/compat_tool/release-keys/allowed_signers" \
        --stage-dir "$WORK/base-stage"
fi

if [[ ! -d "$WORK/ndk-stage" ]]; then
    if [[ -d "$WORK/google-inputs" ]]; then
        src=(--google-inputs "$WORK/google-inputs")
    else
        zips=("$IN"/x86_64-*.zip)
        GOOGLE_ZIP="${GOOGLE_ZIP:-${zips[0]:-}}"
        [[ -n "$GOOGLE_ZIP" ]] || { echo "no Google NDK translation zip (x86_64-*.zip) in $IN" >&2; exit 1; }
        src=(--google-zip "$GOOGLE_ZIP" --save-google-inputs "$WORK/google-inputs")
    fi
    "$WORK/base-stage/compat_tool/tools/lepton-customize" inject --execute \
        --stage-dir "$WORK/base-stage" --output-stage "$WORK/ndk-stage" \
        "${src[@]}" --with-ndk
fi
echo "NDK-STAGE-DONE"
grep -E '"state"|"ndk"|sysbake_required' "$WORK/ndk-stage/STAGE.json"
