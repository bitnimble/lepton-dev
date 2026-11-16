#!/usr/bin/env bash
# Steam Deck, Desktop Mode: installs (or updates in place) the Lepton + Mantis compatibility tool from this
# folder, then the "save report" and "logs" shortcuts. Extra arguments go to Lepton's own installer.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
TOOL_ID=lepton_mantis
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS="$DATA_HOME/applications"
PAUSE=false
args=()
for arg in "$@"; do
    if [[ "$arg" == --pause ]]; then PAUSE=true; else args+=("$arg"); fi
done

finish() {
    local status=$?
    if [[ "$PAUSE" == true ]]; then
        [[ "$status" == 0 ]] && echo "[DONE] Installed." || echo "[FAIL] See the messages above."
        read -r -t 600 -p "Press Enter to close this window." _ || true
    fi
}
trap finish EXIT

installers=("$HERE"/lepton-x86_64-*.install.sh)
[[ ${#installers[@]} == 1 && -f "${installers[0]}" ]] || { echo "Expected one lepton-x86_64-*.install.sh in $HERE" >&2; exit 1; }
[[ ! -d "$DATA_HOME/$TOOL_ID" ]] || args+=(--replace)
bash "${installers[0]}" "${args[@]}"

mkdir -p "$HOME/.local/bin" "$APPS" "$HOME/lepton-logs"
ln -sfn "$DATA_HOME/$TOOL_ID/compat_tool/lepton-mantis/lepton-mantis" "$HOME/.local/bin/lepton-mantis"
cat > "$APPS/lepton-mantis-report.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Lepton: Save crash report
Comment=Bundle recent Lepton + Mantis logs into a .tar.gz on the Desktop
Exec=$HOME/.local/bin/lepton-mantis report
Icon=document-save
Categories=Game;
DESKTOP
cat > "$APPS/lepton-mantis-logs.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Lepton: Open logs
Comment=Per-launch Lepton + Mantis logs (latest/ is the most recent launch)
Exec=xdg-open $HOME/lepton-logs
Icon=folder-documents
Categories=Game;
DESKTOP
for entry in lepton-mantis-report.desktop lepton-mantis-logs.desktop; do
    [[ ! -d "$HOME/Desktop" ]] || install -m 755 "$APPS/$entry" "$HOME/Desktop/$entry"
done

cat <<'NEXT'

Lepton + Mantis is installed. Restart Steam, then follow README.md in this folder:
  1. "Lepton: Add Google game (lepton_mantis)" on the Desktop: pick the game's .apkm, sign in to Google.
  2. In the game's Steam controller settings, enable Touchscreen Native Support.
  3. Launch the game; Mantis opens over it. One-time setup is in README.md.
Logs: ~/lepton-logs/latest/   Report: "Lepton: Save crash report" on the Desktop.
NEXT
