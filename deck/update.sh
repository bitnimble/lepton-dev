#!/usr/bin/env bash
# Pulls this checkout, then runs deck/install.sh (arguments pass through).
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
git -C "$REPO" pull --ff-only || echo "[WARN] git pull failed; installing the checkout as it is"
exec bash "$REPO/deck/install.sh" "$@"
