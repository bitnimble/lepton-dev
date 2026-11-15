#!/bin/bash
# Runs as root inside lepton-runner: base stage from the release bundle, then NDK-translation inject.
set -euo pipefail
W=/var/lib/containers/lepton
IN=$W/inputs
WORK=$W/work
mkdir -p "$WORK"
C="$W/stage/compat_tool/tools/lepton-customize"

if [[ ! -d "$WORK/base-stage" ]]; then
    "$C" --execute \
        --bundle "$IN/lepton-x86_64-v0.2.0-alpha.tar.gz" \
        --checksum "$IN/lepton-x86_64-v0.2.0-alpha.tar.gz.sha256" \
        --signature "$IN/lepton-x86_64-v0.2.0-alpha.tar.gz.sha256.sig" \
        --trusted-signers "$W/stage/compat_tool/release-keys/allowed_signers" \
        --stage-dir "$WORK/base-stage"
fi

if [[ ! -d "$WORK/ndk-stage" ]]; then
    if [[ -d "$WORK/google-inputs" ]]; then
        src=(--google-inputs "$WORK/google-inputs")
    else
        src=(--google-zip "$IN/x86_64-34_r14.zip" --save-google-inputs "$WORK/google-inputs")
    fi
    "$WORK/base-stage/compat_tool/tools/lepton-customize" inject --execute \
        --stage-dir "$WORK/base-stage" --output-stage "$WORK/ndk-stage" \
        "${src[@]}" --with-ndk
fi
echo "NDK-STAGE-DONE"
grep -E '"state"|"ndk"|sysbake_required' "$WORK/ndk-stage/STAGE.json"
