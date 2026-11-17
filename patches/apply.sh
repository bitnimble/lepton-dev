#!/usr/bin/env bash
# Installs the patched release files into a Lepton compat_tool directory.
# Usage: apply.sh <compat_tool dir>
set -euo pipefail
P="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
T="$1"
install -m 755 "$P/lepton-x86_64-entry" "$T/lepton-x86_64-entry"
install -m 644 "$P/liblepton.sh" "$P/properties.sh" "$T/liblepton/"
install -m 644 "$P/liblepton_ndk_auxv.so" "$T/liblepton/ndk_auxv/bin/liblepton_ndk_auxv.so"
