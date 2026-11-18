# Sourced by compat_tool/lepton-x86_64-entry for game launches (waitforexitandrun); $TOOL is compat_tool.
lepton_padmap_entry() {
    local addon="$TOOL/lepton-padmap" logs="${LEPTON_LOG_DIR:-$HOME/lepton-logs}" dir
    dir="$logs/${SteamAppId:-0}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$dir" || return 0
    ln -sfn "$dir" "$logs/latest"
    export LEPTON_SESSION_DIR="$dir"
    if [[ -n "${STEAM_COMPAT_DATA_PATH:-}" && -f "$STEAM_COMPAT_DATA_PATH/lepton-setup-google" ]]; then
        rm -f -- "$STEAM_COMPAT_DATA_PATH/lepton-setup-google"
        export LEPTON_SETUP_GOOGLE=true LEPTON_GOOGLE_SIGNIN=true
    fi
    env -u LD_PRELOAD setsid "$addon/lepton-padmap" session </dev/null >/dev/null 2>&1 &
    exec > >(tee -a "$dir/lepton.log") 2>&1
    printf 'lepton-padmap: session %s, args: %s, NDK mode: %s\n' "$dir" "$*" "${LEPTON_NDK_TRANSLATION_MODE:-auto}"
    python3 "$addon/ndk-translation/fix.py" "$TOOL/images/rootfs" "$TOOL/images/rootfs_overlay" || true
    python3 "$addon/ndk-translation/cpuinfo.py" "$TOOL/images/rootfs" "$TOOL/images/rootfs_overlay" || true
    # Steam's shader-cache layer segfaults the nested gamescope it gets injected into
    export VK_LOADER_LAYERS_DISABLE="${VK_LOADER_LAYERS_DISABLE:+$VK_LOADER_LAYERS_DISABLE,}*fossilize*"
    lepton_padmap_plain_gamescope
}

lepton_padmap_plain_gamescope() {
    local real=/usr/bin/gamescope bin="$HOME/.cache/lepton-padmap/bin" copy
    [[ -x "$real" ]] && mkdir -p "$bin" || return 0
    if ! cmp -s "$real" "$bin/gamescope"; then
        # a plain copy drops cap_sys_nice: a capable nested gamescope's /proc/<pid>/fdinfo is unreadable, and
        # Steam's performance overlay (mangoapp) aborts on it in a loop
        copy="$(mktemp "$bin/gamescope.XXXXXX")" && cp "$real" "$copy" && chmod 755 "$copy" &&
            mv -f "$copy" "$bin/gamescope" || { rm -f "${copy:-}"; return 0; }
    fi
    export PATH="$bin:$PATH"
}
lepton_padmap_entry "$@" || true
