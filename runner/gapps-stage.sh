#!/bin/bash
# Runs as dev inside lepton-runner: NDK + GApps injected stage from the clean base stage.
set -euo pipefail
WORK=/var/lib/containers/lepton/work
if [[ ! -d "$WORK/gapps-stage" ]]; then
    "$WORK/base-stage/compat_tool/tools/lepton-customize" inject --execute \
        --stage-dir "$WORK/base-stage" --output-stage "$WORK/gapps-stage" \
        --google-inputs "$WORK/google-inputs" --with-ndk --with-gapps
fi
echo "GAPPS-STAGE-DONE"
grep -E '"state"|"ndk"|"gapps"' "$WORK/gapps-stage/STAGE.json"
