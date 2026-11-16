# Sourced (as root inside lepton-runner) before running the Lepton launcher.
W=/var/lib/containers/lepton
export HOME="$W/home"
export XDG_RUNTIME_DIR=/run/user/0
export LEPTON_FORCE_SOFTWARE=true
export APP_WANTS_FLATSCREEN=true
export LEPTON_NO_BRIDGE=true
export TERM=dumb
export LEPTON_ADB=/usr/bin/adb
STAGE="${LEPTON_STAGE:-$W/stage}"
export PATH="$STAGE/tools/bin:$PATH"
LEPTON="$STAGE/compat_tool/lepton"

ensure_display() {
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    ensure_audio
    if [[ ! -S "$XDG_RUNTIME_DIR/gamescope-0" ]]; then
        weston --no-config --backend=headless --renderer=pixman --width=1280 --height=800 \
            --socket=gamescope-0 --log="$W/weston.log" &
        for _ in $(seq 50); do [[ -S "$XDG_RUNTIME_DIR/gamescope-0" ]] && break; sleep 0.1; done
    fi
    [[ -S "$XDG_RUNTIME_DIR/gamescope-0" ]]
}

ensure_audio() {
    [[ -S "$XDG_RUNTIME_DIR/pulse/native" ]] && return
    pipewire >> "$W/pipewire.log" 2>&1 &
    for _ in $(seq 50); do [[ -S "$XDG_RUNTIME_DIR/pipewire-0" ]] && break; sleep 0.1; done
    wireplumber >> "$W/pipewire.log" 2>&1 &
    pipewire-pulse >> "$W/pipewire.log" 2>&1 &
    for _ in $(seq 50); do [[ -S "$XDG_RUNTIME_DIR/pulse/native" ]] && break; sleep 0.1; done
    [[ -S "$XDG_RUNTIME_DIR/pulse/native" ]]
}

ensure_cgroup() {
    mkdir -p "/sys/fs/cgroup/lepton-$1"
}
