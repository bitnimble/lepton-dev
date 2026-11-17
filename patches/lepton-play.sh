#!/bin/bash
# Play-install support, sourced after google_games.sh so these win. Both modes are
# opt-in via env; with neither set the stock apk-driven launch path is untouched.
#   LEPTON_PLAY_ONLY=true        boot to the Play Store and install nothing (sign
#                                in and download a game into this profile's data)
#   LEPTON_LAUNCH_PACKAGE=<pkg>  launch an already-installed package, no apk file

function lepton_play_only() { [[ "${LEPTON_PLAY_ONLY:-false}" == true ]]; }

# With no apk file the stock get_app_id is empty and the lepton script aborts the
# steamlaunch ("no package name found"). In the no-apk modes the package is known
# up front, so report it; is_app stays false (no apk), so nothing is installed.
function get_app_id()
{
    if [[ -n "${LEPTON_LAUNCH_PACKAGE:-}" ]]; then print "${LEPTON_LAUNCH_PACKAGE}"; return; fi
    if lepton_play_only; then print "${PLAY_STORE_PACKAGE}"; return; fi
    if is_app && [[ -z "${APP_PACKAGE_ID}" ]]; then
        APP_PACKAGE_ID="$(extract_app_id "$(get_apk_path)")"
    fi
    print "${APP_PACKAGE_ID}"
}

# Package whose process ends the session (process observer) and that the launch rc starts.
function lepton_observed_app_id()
{
    if [[ -n "${LEPTON_LAUNCH_PACKAGE:-}" ]]; then print "${LEPTON_LAUNCH_PACKAGE}"; return; fi
    if lepton_play_only || google_signin_mode; then print "${PLAY_STORE_PACKAGE}"; return; fi
    print "$(get_app_id)"
}

# Play-only boots a fresh profile with nothing to install; report success so the
# boot is released (install_app's success path calls continue_boot_after_bake)
# without running adb against a non-existent apk.
eval "lepton_orig_$(declare -f install_app)"
function install_app()
{
    if lepton_play_only; then
        println "Play-only launch: no app to install"
        return 0
    fi
    lepton_orig_install_app "$@"
}

# The command the app-launch rc runs once the profile is up.
function lepton_launch_commands()
{
    if [[ -n "${LEPTON_LAUNCH_PACKAGE:-}" ]]; then
        # Resolve the launcher activity from the installed package at boot, so a
        # profile keyed only by package name still starts the right component.
        # No inner quotes: mounting.sh already wraps this whole string in "...",
        # and a resolved component name never contains spaces.
        print "am start -n \$(cmd package resolve-activity --brief -c android.intent.category.LAUNCHER ${LEPTON_LAUNCH_PACKAGE} | tail -1)"
        return
    fi
    if lepton_play_only || google_signin_mode; then
        print "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p ${PLAY_STORE_PACKAGE}"
        return
    fi
    print "$(run_app_commands "$(get_app_id)" "$(get_app_activity)" no-force-stop)"
}
