#!/bin/bash
# Host-side: builds manager/ in a Debian 12 container (glibc 2.36, older than any SteamOS 3) into
# deck/lepton-manager. With --test, runs the tests and clippy instead.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=lepton-manager-build
docker build -q -t "$IMAGE" - >/dev/null <<'EOF'
FROM rust:1-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends libudev-dev pkg-config \
    && rm -rf /var/lib/apt/lists/* && rustup component add clippy
EOF
run() {
    # Sources go in over stdin and results come back over stdout: this dev container's paths aren't the docker
    # host's, so bind mounts can't be used. The named volumes keep crates and build output between runs.
    tar -C "$R/manager" --exclude=./target -cf - . | docker run --rm -i \
        -v lepton-manager-cargo:/usr/local/cargo/registry -v lepton-manager-target:/build/target \
        -w /build "$IMAGE" bash -c "tar -xf - && $1"
}
if [[ "${1:-}" == --test ]]; then
    run 'cargo test --locked >&2 && cargo clippy --locked --all-targets -- -D warnings >&2'
    exit
fi
run 'cargo build --locked --release >&2 && cat target/release/lepton-manager' >| "$R/deck/lepton-manager.new"
chmod 755 "$R/deck/lepton-manager.new"
mv "$R/deck/lepton-manager.new" "$R/deck/lepton-manager"
ls -la "$R/deck/lepton-manager"
