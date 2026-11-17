# Sourced by the host-side bin/ scripts: the runner container + its root path in one place.
W=/var/lib/containers/lepton
RUNNER="${LEPTON_RUNNER:-lepton-runner}"
BIN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

runner_exec() { docker exec "$RUNNER" "$@"; }

# Stream a host file into the runner (docker cp is unreliable under sysbox).
put() { docker exec -i "$RUNNER" sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }

# Stream a runner file out to the host (same reason docker cp is avoided).
pull_file() { docker exec "$RUNNER" cat "$1" >| "$2"; }

# Screenshot a running context to a host path.
pull_screen() {
    local ctx="$1" out="$2" remote="/data/local/tmp/shot.png"
    docker exec "$RUNNER" sh -c \
        "podman exec lepton-$ctx /system/bin/screencap -p $remote && podman exec lepton-$ctx /system/bin/cat $remote" >| "$out"
}

# push.sh + setup-rootful: get the runner's code and stage current before a launch.
launch_prepare() {
    bash "$BIN/push.sh" >/dev/null
    runner_exec bash "$W/setup-rootful.sh" >/dev/null
}

# Stop a context's prior session and drop its run artifacts.
launch_clear() {
    runner_exec bash -c "source '$W/lepton-env.sh' && stop_ctx '$1' && rm -f '$W/run/$1.log' '$W/run/$1.png'"
}
