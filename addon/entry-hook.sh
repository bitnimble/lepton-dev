# Sourced by compat_tool/lepton-x86_64-entry for game launches (waitforexitandrun); $TOOL is compat_tool.
lepton_mantis_entry() {
    local addon="$TOOL/lepton-mantis" logs="${LEPTON_LOG_DIR:-$HOME/lepton-logs}" dir mode=""
    dir="$logs/${SteamAppId:-0}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir" || return 0
    ln -sfn "$dir" "$logs/latest"
    export LEPTON_SESSION_DIR="$dir"
    if [[ -z "${LEPTON_NDK_TRANSLATION_MODE:-}" ]]; then
        mode="$(python3 "$addon/ndk-mode.py" "$addon/ndk-modes" "${@: -1}" 2>/dev/null || true)"
        [[ -z "$mode" ]] || export LEPTON_NDK_TRANSLATION_MODE="$mode"
    fi
    setsid "$addon/lepton-mantis" session </dev/null >/dev/null 2>&1 &
    exec > >(tee -a "$dir/lepton.log") 2>&1
    printf 'lepton-mantis: session %s, args: %s, NDK mode: %s\n' "$dir" "$*" "${LEPTON_NDK_TRANSLATION_MODE:-auto}"
}
lepton_mantis_entry "$@" || true
