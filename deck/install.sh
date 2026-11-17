#!/usr/bin/env bash
# Steam Deck, Desktop Mode: installs or updates Lepton + Padmap from this checkout. The Android bundle is the newest
# one in bundle/ (lepton-x86_64-<id>.tar.gz, .tar.gz.sha256, .install.sh), else built by deck/build-bundle.sh, and
# is installed with Lepton's own installer if it isn't already; then the checkout's add-on and patched release files
# replace the installed tool's and the desktop shortcuts are (re)made. Extra arguments go to Lepton's installer.
set -euo pipefail
shopt -s nullglob
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
TOOL="$DATA_HOME/lepton_padmap"
ADDON="$TOOL/compat_tool/lepton-padmap"
LAYOUTS="${XDG_CONFIG_HOME:-$HOME/.config}/padmap/layouts"
APPS="$DATA_HOME/applications"
PAUSE=false
args=()
for arg in "$@"; do
    if [[ "$arg" == --pause ]]; then PAUSE=true; else args+=("$arg"); fi
done

finish() {
    local status=$?
    if [[ "$PAUSE" == true ]]; then
        [[ "$status" == 0 ]] && echo "[DONE] Lepton + Padmap is up to date." || echo "[FAIL] See the messages above."
        read -r -t 600 -p "Press Enter to close this window." _ || true
    fi
}
trap finish EXIT

installed_id() { sed -n 's/^ *"bundle_id": *"\(.*\)",\{0,1\}$/\1/p' "$TOOL/BUNDLE.json" 2>/dev/null; }

find_bundles() {  # newest first
    bundles=("$REPO"/bundle/lepton-x86_64-*.tar.gz)
    # never ls an empty list: with no arguments it lists the current directory
    ((${#bundles[@]} == 0)) || mapfile -t bundles < <(ls -t -- "${bundles[@]}")
}

if command -v podman >/dev/null 2>&1 && [[ -n "$(podman ps -q --filter label=lepton=true 2>/dev/null)" ]]; then
    echo "A Lepton game is running; quit it first." >&2
    exit 1
fi

source "$REPO/deck/bundle.env"
installed="$(installed_id)"
find_bundles
# A bundle copied into bundle/ wins; otherwise build when nothing, or an older auto-built bundle, is installed.
if ((${#bundles[@]} == 0)) && [[ -z "$installed" || ( "$installed" == auto-* && "$installed" != "$BUNDLE_ID" ) ]]; then
    echo "Building the Android bundle from Lepton's and Google's downloads (about 2 GB, 15+ minutes)..."
    bash "$REPO/deck/build-bundle.sh"
    find_bundles
fi
if ((${#bundles[@]})); then
    newest="${bundles[0]}"
    id="${newest##*/lepton-x86_64-}"
    id="${id%.tar.gz}"
    if [[ "$id" == "$installed" ]]; then
        echo "[PASS] Bundle $id is installed"
    else
        [[ ! -d "$TOOL" ]] || args+=(--replace)
        bash "${newest%.tar.gz}.install.sh" "${args[@]}"
    fi
    for old in "${bundles[@]}"; do
        rm -f -- "$old" "$old.sha256" "${old%.tar.gz}.install.sh"
    done
fi
[[ -d "$TOOL/compat_tool" ]] || { echo "Lepton + Padmap isn't installed; see the messages above." >&2; exit 1; }
bash "$REPO/deck/fetch-artifacts.sh"
echo "[PASS] Game Manager, Padmap and NDK shim match deck/artifacts.env"

rm -rf "$ADDON.new"
cp -r "$REPO/addon" "$ADDON.new"
rm -rf "$ADDON"
mv "$ADDON.new" "$ADDON"
bash "$REPO/patches/apply.sh" "$TOOL/compat_tool"
echo "[PASS] Add-on and patches updated from $REPO ($(git -C "$REPO" log -1 --format='%h %cs' 2>/dev/null || echo 'not a git checkout'))"

mkdir -p "$HOME/.local/bin" "$APPS" "$HOME/lepton-logs" "$LAYOUTS"
ln -sfn "$ADDON/lepton-padmap" "$HOME/.local/bin/lepton-padmap"
# The Game Manager does what this install's desktop icons and Lepton's per-tool Google icons would
for dir in "$APPS" "$HOME/Desktop"; do
    rm -f -- "$dir"/lepton-padmap-*.desktop "$dir"/lepton-x86_64-google-*-lepton_padmap.desktop
done
MANAGER="$APPS/lepton-padmap-manager.desktop"
printf '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec="%s"\nIcon=%s\nCategories=Game;\n' \
    "Lepton Game Manager" "Add Android games to Steam and manage them" "$REPO/deck/lepton-manager" \
    input-gaming >"$MANAGER"
[[ ! -d "$HOME/Desktop" ]] || install -m 755 "$MANAGER" "$HOME/Desktop/lepton-padmap-manager.desktop"
echo "[PASS] Desktop shortcut: Lepton Game Manager"
# Steam's local debugging port, which the manager changes the library through; Steam reads this at start
if [[ -d "$HOME/.local/share/Steam" ]]; then
    touch "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
fi
if "$REPO/deck/lepton-manager" --add-to-steam; then
    echo "[PASS] Lepton Game Manager is under Non-Steam in your Steam library"
else
    echo "[WARN] Couldn't add Lepton Game Manager to Steam; open it from the desktop and pick Add Lepton Game Manager to Steam"
fi
