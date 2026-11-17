#!/bin/bash
# Host-side: screenshot a running context to data/screens/<name>.png
# Usage: shot.sh <ctx> <name>
set -euo pipefail
source "$(dirname "$0")/lib.sh"
CTX="$1"; NAME="$2"
OUT="$(cd "$(dirname "$0")/.." && pwd)/data/screens/$NAME.png"
mkdir -p "$(dirname "$OUT")"
pull_screen "$CTX" "$OUT"
file "$OUT"
