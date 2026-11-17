# Sourced by lepton-padmap's session watcher for a "Set up Google services" launch (LEPTON_SETUP_GOOGLE=true, set by
# entry-hook.sh from the manager's <compatdata>/lepton-setup-google): the Play Store is open, kept alive through its
# restarts by Google sign-in mode, while Play updates itself and Play services.
SETUP_MIN_SECONDS=120
SETUP_QUIET_SECONDS=60
SETUP_QUIET_KIB=64
SETUP_MAX_SECONDS=1200

setup_google() {
    local start=$SECONDS quiet_since=$SECONDS last now
    log "setting up Google services ($(google_versions))"
    install_helper || log "installing the helper app failed; the Play Store stays on screen"
    last="$(received_bytes)"
    while alive; do
        show_wait
        sleep 5
        now="$(received_bytes)"
        ((now - last <= SETUP_QUIET_KIB * 1024)) || quiet_since=$SECONDS
        last="$now"
        # Play starts updating a minute or so after boot; its downloads going quiet is the only "done" it gives
        if ((SECONDS - start >= SETUP_MIN_SECONDS && SECONDS - quiet_since >= SETUP_QUIET_SECONDS)); then
            log "Google services are up to date ($(google_versions)); powering off"
            break
        fi
        if ((SECONDS - start >= SETUP_MAX_SECONDS)); then
            log "still downloading after ${SETUP_MAX_SECONDS}s ($(google_versions)); powering off"
            break
        fi
    done
    # Android powering off ends the launch the way Steam's Exit does
    guest reboot -p >/dev/null 2>&1
}

install_helper() {
    podman exec -i "$C" sh -c "cat > /data/local/tmp/lepton-helper.apk" <"$ADDON/lepton-helper.apk" &&
        # cmd_real, not pm: Lepton's cmd wrapper treats every install as the game and moves the game's APKs away
        guest cmd_real package install -r /data/local/tmp/lepton-helper.apk </dev/null >/dev/null
}

show_wait() {
    guest am start -n app.lepton.helper/.WaitActivity --es title "Updating Google Play services" \
        --es detail "This closes by itself when it's done." >/dev/null 2>&1
}

received_bytes() { guest cat /proc/net/dev 2>/dev/null | awk 'NR > 2 && $1 != "lo:" { sum += $2 } END { print sum + 0 }'; }

google_versions() {
    local package
    for package in com.android.vending com.google.android.gms; do
        printf '%s %s ' "$package" "$(guest dumpsys package "$package" 2>/dev/null | sed -n 's/^ *versionName=//p' | head -1)"
    done
}
