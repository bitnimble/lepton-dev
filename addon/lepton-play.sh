#!/bin/bash
# Games installed from the Play Store. A "Play slot" is a placeholder .apkm (a text file starting with
# lepton-play-slot) that Steam launches like any game; its Android profile (the shortcut's compatdata) holds a
# game installed from the Play Store and launched by package name, recorded in <compatdata>/lepton-launch-package.
#   nothing recorded, LEPTON_PLAY_ONLY=true or a Google sign-in launch (also <compatdata>/lepton-open-play-store,
#     for one launch of any game): open the Play Store; when it stops, the newest installed app becomes the
#     slot's game
#   LEPTON_LAUNCH_PACKAGE=<pkg>: launch that package and record it
#   a recorded package the profile doesn't have (uninstalled, profile reset): open its Play Store page
# Sourced at the end of liblepton.sh, so these wrap the originals; anything that is not a slot is untouched.

PLAY_SLOT_MARKER=lepton-play-slot

# One launch with the Play Store, requested by the Lepton Game Manager.
if [[ -n "${STEAM_COMPAT_DATA_PATH:-}" && -f "${STEAM_COMPAT_DATA_PATH}/lepton-open-play-store" ]]; then
    rm -f -- "${STEAM_COMPAT_DATA_PATH}/lepton-open-play-store"
    export LEPTON_GOOGLE_SIGNIN=true
fi

eval "lepton_orig_$(declare -f prepare_apkm)"
eval "lepton_orig_$(declare -f get_app_id)"
eval "lepton_orig_$(declare -f get_app_activity)"
eval "lepton_orig_$(declare -f lepton_observed_app_id)"
eval "lepton_orig_$(declare -f lepton_launch_commands)"
eval "lepton_orig_$(declare -f is_app_baked)"
eval "lepton_orig_$(declare -f get_app_mount_dir)"
eval "lepton_orig_$(declare -f install_app)"
eval "lepton_orig_$(declare -f kill_container)"

function lepton_play_record() { print "${STEAM_COMPAT_DATA_PATH}/lepton-launch-package"; }

function prepare_apkm()
{
    if [[ "$(head -c "${#PLAY_SLOT_MARKER}" -- "$1" 2>/dev/null)" != "$PLAY_SLOT_MARKER" ]]; then
        lepton_orig_prepare_apkm "$@"
        return
    fi
    [[ -n "${STEAM_COMPAT_DATA_PATH:-}" ]] || die "Play games need a Steam launch (STEAM_COMPAT_DATA_PATH)."
    export LEPTON_PLAY_SLOT=1 LEPTON_PLAY_PACKAGE="" LEPTON_PLAY_MISSING=""
    # An app path makes is_app true, which the launch rc needs; an empty APKM dir keeps /data/steam_app empty.
    export LEPTON_APKM_DIR="${STEAM_COMPAT_DATA_PATH}/lepton-play-slot"
    export APP_PATH="${LEPTON_APKM_DIR}/base.apk"
    mkdir -p -- "$LEPTON_APKM_DIR"
    # A slot installs nothing, so a booted profile is complete: a first boot cut off before Lepton marked it
    # would otherwise fail installation validation on every launch.
    [[ ! -f "${STEAM_COMPAT_DATA_PATH}/baked/data_overlay/system/packages.xml" ]] || touch -- "$(app_install_complete_path)"
    if [[ -n "${LEPTON_LAUNCH_PACKAGE:-}" ]]; then
        LEPTON_PLAY_PACKAGE="$LEPTON_LAUNCH_PACKAGE"
    elif [[ "${LEPTON_PLAY_ONLY:-false}" != true ]] && ! google_signin_mode; then
        LEPTON_PLAY_PACKAGE="$(cat "$(lepton_play_record)" 2>/dev/null || true)"
    fi
    [[ -z "$LEPTON_PLAY_PACKAGE" || "$LEPTON_PLAY_PACKAGE" =~ ^[A-Za-z0-9_.]+$ ]] ||
        die "Not an Android package name: $LEPTON_PLAY_PACKAGE"
    [[ -z "${LEPTON_LAUNCH_PACKAGE:-}" ]] || printf '%s\n' "$LEPTON_PLAY_PACKAGE" > "$(lepton_play_record)"
    if [[ -n "$LEPTON_PLAY_PACKAGE" ]] && ! lepton_play_installed "$LEPTON_PLAY_PACKAGE"; then
        println "Play game: $LEPTON_PLAY_PACKAGE isn't installed in this profile, opening its Play Store page"
        LEPTON_PLAY_MISSING="$LEPTON_PLAY_PACKAGE" LEPTON_PLAY_PACKAGE=""
        return
    fi
    println "Play game: ${LEPTON_PLAY_PACKAGE:-none yet, opening the Play Store}"
}

# By its code dir (/data/app/~~<id>/<package>-<id>): packages.xml keeps entries for apps that are gone. Unknown
# counts as installed, so a profile that can't be read never sends every launch to the Play Store.
function lepton_play_installed()
{
    local apps="${STEAM_COMPAT_DATA_PATH}/baked/data_overlay/app" found
    [[ -d "$apps" ]] || return 0
    found="$(as_container_owner find "$apps" -mindepth 2 -maxdepth 2 -type d -name "$1-*" -print -quit)" || return 0
    [[ -n "$found" ]]
}

function get_app_id()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_get_app_id "$@"; return; }
    print "${LEPTON_PLAY_PACKAGE:-${PLAY_STORE_PACKAGE}}"
}

# Only checked for presence on the host; the slot's launcher activity is resolved in Android at boot.
function get_app_activity()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_get_app_activity "$@"; return; }
    print launcher
}

function lepton_observed_app_id()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_lepton_observed_app_id "$@"; return; }
    get_app_id
}

function lepton_launch_commands()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_lepton_launch_commands "$@"; return; }
    if [[ -n "${LEPTON_PLAY_MISSING}" ]]; then
        print "am start -a android.intent.action.VIEW -d market://details?id=${LEPTON_PLAY_MISSING} -p ${PLAY_STORE_PACKAGE}"
        return
    fi
    if [[ -z "${LEPTON_PLAY_PACKAGE}" ]]; then
        print "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p ${PLAY_STORE_PACKAGE}"
        return
    fi
    # No $ (init expands rc exec args twice and drops a line with $( in it) and no inner quotes (mounting.sh
    # wraps this in "...").
    print "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER ${LEPTON_PLAY_PACKAGE} | tail -n 1 | xargs am start -n"
}

# A slot never has an apk overlay to validate; its profile is set up once its first boot completes.
function is_app_baked()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_is_app_baked "$@"; return; }
    [[ -f "$(app_install_complete_path)" ]]
}

# The empty slot dir stays at /data/steam_app: mounting it at the game's code dir would hide the game.
function get_app_mount_dir()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_get_app_mount_dir "$@"; return; }
    print data/steam_app
}

# A slot has no apk; its game is installed by the Play Store. Success releases the boot.
function install_app()
{
    [[ -n "${LEPTON_PLAY_SLOT:-}" ]] || { lepton_orig_install_app "$@"; return; }
    println "Play game: nothing to install"
}

# Teardown stops Android here, while it is still running: after a Play Store session, record the newest app.
function kill_container()
{
    [[ -z "${LEPTON_PLAY_SLOT:-}" || -n "${LEPTON_PLAY_PACKAGE}${LEPTON_PLAY_MISSING}" ]] || lepton_play_record_newest
    lepton_orig_kill_container "$@"
}

function lepton_play_record_newest()
{
    local newest
    newest="$(podman exec "lepton-${LEPTON_CONTEXT}" /system/bin/sh -c \
        'for p in $(pm list packages -3 | sed s/package://); do
             [ "$p" = app.padmap ] && continue
             echo "$(dumpsys package "$p" | sed -n "s/.*firstInstallTime=//p" | head -1)|$p"
         done | sort -r | head -1 | sed "s/.*|//"' 2>/dev/null)" || return 0
    [[ "$newest" =~ ^[A-Za-z0-9_.]+$ ]] || return 0
    printf '%s\n' "$newest" > "$(lepton_play_record)"
    println "Play game: launches $newest from now on"
}
