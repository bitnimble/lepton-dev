#!/bin/bash
# Host-side: launcher's own lines (no colourised logcat, no Steam manifest noise) for a context.
CTX="$1"; N="${2:-15}"
docker exec lepton-runner bash -c "grep -v -P '\x1b|appmanifest|^\s*$' '/var/lib/containers/lepton/run/$CTX.log' | tail -$N"
