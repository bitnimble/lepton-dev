#!/usr/bin/env bash
# Steam Deck, Desktop Mode: installs or updates Lepton + Mantis from this checkout. The newest bundle in bundle/
# (lepton-x86_64-<id>.tar.gz, .tar.gz.sha256, .install.sh) is installed with Lepton's own installer if it isn't
# already, then the checkout's add-on and Steam entry are copied over the installed tool and the desktop
# shortcuts are (re)made. Extra arguments go to Lepton's installer.
set -euo pipefail
shopt -s nullglob
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
TOOL="$DATA_HOME/lepton_mantis"
APPS="$DATA_HOME/applications"
PAUSE=false
args=()
for arg in "$@"; do
    if [[ "$arg" == --pause ]]; then PAUSE=true; else args+=("$arg"); fi
done

finish() {
    local status=$?
    if [[ "$PAUSE" == true ]]; then
        [[ "$status" == 0 ]] && echo "[DONE] Lepton + Mantis is up to date." || echo "[FAIL] See the messages above."
        read -r -t 600 -p "Press Enter to close this window." _ || true
    fi
}
trap finish EXIT

installed_id() { sed -n 's/^ *"bundle_id": *"\(.*\)",\{0,1\}$/\1/p' "$TOOL/BUNDLE.json" 2>/dev/null; }

if command -v podman >/dev/null 2>&1 && [[ -n "$(podman ps -q --filter label=lepton=true 2>/dev/null)" ]]; then
    echo "A Lepton game is running; quit it first." >&2
    exit 1
fi

bundles=("$REPO"/bundle/lepton-x86_64-*.tar.gz)
if ((${#bundles[@]})); then
    newest="${bundles[-1]}"
    id="${newest##*/lepton-x86_64-}"
    id="${id%.tar.gz}"
    if [[ "$id" == "$(installed_id)" ]]; then
        echo "[PASS] Bundle $id is installed"
    else
        [[ ! -d "$TOOL" ]] || args+=(--replace)
        bash "${newest%.tar.gz}.install.sh" "${args[@]}"
        for old in "${bundles[@]:0:${#bundles[@]}-1}"; do
            rm -f -- "${old%.tar.gz}".*
        done
    fi
fi
[[ -d "$TOOL/compat_tool/lepton-mantis" ]] || {
    echo "Lepton + Mantis isn't installed yet: copy a bundle into $REPO/bundle/ first (see deck/README.md)." >&2
    exit 1
}

cp -r "$REPO/addon/." "$TOOL/compat_tool/lepton-mantis/"
install -m 755 "$REPO/patches/lepton-x86_64-entry" "$TOOL/compat_tool/lepton-x86_64-entry"
echo "[PASS] Add-on updated from $REPO ($(git -C "$REPO" log -1 --format='%h %cs' 2>/dev/null || echo 'not a git checkout'))"

mkdir -p "$HOME/.local/bin" "$APPS" "$HOME/lepton-logs"
ln -sfn "$TOOL/compat_tool/lepton-mantis/lepton-mantis" "$HOME/.local/bin/lepton-mantis"
shortcut() {
    local file="$1" name="$2" comment="$3" exec="$4" icon="$5"
    printf '[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=%s\nIcon=%s\nCategories=Game;\n' \
        "$name" "$comment" "$exec" "$icon" >"$APPS/$file"
    [[ ! -d "$HOME/Desktop" ]] || install -m 755 "$APPS/$file" "$HOME/Desktop/$file"
}
shortcut lepton-mantis-update.desktop "Lepton: Update Lepton + Mantis" "git pull this checkout, then install it" \
    "konsole -e bash \"$REPO/deck/update.sh\" --pause" system-software-update
shortcut lepton-mantis-report.desktop "Lepton: Save crash report" \
    "Bundle recent Lepton + Mantis logs into a .tar.gz on the Desktop" "$HOME/.local/bin/lepton-mantis report" \
    document-save
shortcut lepton-mantis-logs.desktop "Lepton: Open logs" \
    "Per-launch Lepton + Mantis logs (latest/ is the most recent launch)" "xdg-open $HOME/lepton-logs" \
    folder-documents
echo "[PASS] Desktop shortcuts: Update, Save crash report, Open logs"
