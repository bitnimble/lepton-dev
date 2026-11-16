# Sourced by compat_tool/lepton-x86_64-entry for game launches (waitforexitandrun); $TOOL is compat_tool.
lepton_padmap_entry() {
    local addon="$TOOL/lepton-padmap" logs="${LEPTON_LOG_DIR:-$HOME/lepton-logs}" dir mode=""
    dir="$logs/${SteamAppId:-0}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir" || return 0
    ln -sfn "$dir" "$logs/latest"
    export LEPTON_SESSION_DIR="$dir"
    if [[ -z "${LEPTON_NDK_TRANSLATION_MODE:-}" ]]; then
        mode="$(python3 "$addon/ndk-mode.py" "$addon/ndk-modes" "${@: -1}" 2>/dev/null || true)"
        [[ -z "$mode" ]] || export LEPTON_NDK_TRANSLATION_MODE="$mode"
    fi
    setsid "$addon/lepton-padmap" session </dev/null >/dev/null 2>&1 &
    exec > >(tee -a "$dir/lepton.log") 2>&1
    printf 'lepton-padmap: session %s, args: %s, NDK mode: %s\n' "$dir" "$*" "${LEPTON_NDK_TRANSLATION_MODE:-auto}"
    lepton_padmap_plain_gamescope
}

lepton_padmap_plain_gamescope() {
    local real=/usr/bin/gamescope bin="$HOME/.cache/lepton-padmap/bin"
    [[ -x "$real" ]] && mkdir -p "$bin" || return 0
    if ! cmp -s "$real" "$bin/gamescope"; then
        cp "$real" "$bin/gamescope.new" && mv -f "$bin/gamescope.new" "$bin/gamescope" || return 0
    fi
    # copy drops cap_sys_nice: a capable nested gamescope's /proc/<pid>/fdinfo is unreadable, and Steam's
    # performance overlay (mangoapp) aborts on it in a loop, freezing the game on every core dump
    export PATH="$bin:$PATH"
}
lepton_padmap_entry "$@" || true
