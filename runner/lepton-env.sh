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
        weston --no-config --backend=headless --renderer=pixman \
            --width="${LEPTON_WIDTH:-1280}" --height="${LEPTON_HEIGHT:-800}" \
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

# Wait up to $3s (default 900) for launcher pid $2 to log "Boot complete!" to $1.
wait_boot() {
    local log="$1" lpid="$2" timeout="${3:-900}" n
    for ((n = 0; n < timeout; n++)); do
        grep -q "Boot complete!" "$log" && return 0
        kill -0 "$lpid" 2>/dev/null || { echo "launcher exited early"; tail -40 "$log"; return 1; }
        sleep 1
    done
    echo "boot timeout"; tail -40 "$log"; return 1
}

stop_ctx() {
    local pidfile="$W/run/$1.pid" pid n
    pid="$(cat "$pidfile" 2>/dev/null)" || true
    # SIGTERM first: Lepton's teardown runs with Android still up (Play slots record their game there)
    if [[ -n "$pid" ]] && kill -TERM "$pid" 2>/dev/null; then
        for ((n = 0; n < 60; n++)); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    fi
    podman rm -f "lepton-$1" >/dev/null 2>&1 || true
    rm -f "$pidfile"
}

# Screenshot context $1 to host path $2.
screencap_ctx() {
    podman exec "lepton-$1" /system/bin/screencap -p /data/local/tmp/screen.png
    podman cp "lepton-$1:/data/local/tmp/screen.png" "$2"
}
