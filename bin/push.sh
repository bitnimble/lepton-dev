#!/bin/bash
# Copies runner scripts, the patched launcher library and the Lepton + Padmap add-on into lepton-runner
# (docker cp is unreliable under sysbox).
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
W=/var/lib/containers/lepton
put() { docker exec -i lepton-runner sh -c "mkdir -p \"\$(dirname '$2')\" && cat >| '$2' && chmod ${3:-644} '$2'" < "$1"; }
put "$R/runner/lepton-env.sh" "$W/lepton-env.sh"
put "$R/runner/pipewire-null-sink.conf" /etc/pipewire/pipewire.conf.d/lepton-null-sink.conf
put "$R/runner/ws-scrcpy.yaml" "$W/ws-scrcpy.yaml"
put "$R/runner/ws-scrcpy-lepton.patch" "$W/ws-scrcpy-lepton.patch"
put "$R/runner/vpad.c" "$W/vpad.c"
put "$R/runner/deck-record-sysbake.py" "$W/deck-record-sysbake.py"
put "$R/patches/lepton-x86_64-entry" "$W/patches/lepton-x86_64-entry" 755
put "$R/patches/c2-input-surface.patch" "$W/patches/c2-input-surface.patch"
for script in setup-rootful run-apk-rootful run-steamlaunch-rootful sysbake-rootful ndk-stage gapps-stage watch \
    ws-scrcpy ws-scrcpy-setup vpad build-deck-bundle; do
    put "$R/runner/$script.sh" "$W/$script.sh" 755
done
A="$W/addon"
tar -C "$R/addon" -cf - . | docker exec -i lepton-runner sh -c "rm -rf '$A' && mkdir -p '$A' && tar -C '$A' -xf -"
for stage in stage ndk gapps; do
    T="$W/$stage/compat_tool"
    docker exec lepton-runner test -d "$T/liblepton" || continue
    for lib in liblepton properties; do
        put "$R/patches/$lib.sh" "$T/liblepton/$lib.sh"
    done
    put "$R/patches/lepton-x86_64-entry" "$T/lepton-x86_64-entry" 755
    docker exec lepton-runner sh -c "rm -rf '$T/lepton-padmap' && cp -a '$A' '$T/lepton-padmap'"
done
# Rebuild patches/ndk_auxv.c (mode-defer + guest-consistent /proc + guest-mmap low-bias) and
# install it over each active stage's bundled shim. The shim's bridge build-id check means a
# newer NDK build disables its private-ABI pokes instead of misbehaving, so this stays safe
# across bundle updates; re-run after any re-stage, like the liblepton.sh override above.
put "$R/patches/ndk_auxv.c" "$W/ndk_auxv.c"
if docker exec lepton-runner sh -c 'command -v clang >/dev/null 2>&1'; then
    docker exec lepton-runner sh -c "clang --target=x86_64-linux-android34 -O2 -fPIC -shared -nostdlib \
        -fvisibility=hidden -Wall -Wextra -Werror -Wl,-soname,liblepton_ndk_auxv.so \
        -o '$W/liblepton_ndk_auxv.so' '$W/ndk_auxv.c'"
    for stage in stage ndk gapps; do
        D="$W/$stage/compat_tool/liblepton/ndk_auxv"
        docker exec lepton-runner test -d "$D/bin" || continue
        docker exec lepton-runner sh -c "! [ -x '$D/validate.sh' ] || bash '$D/validate.sh' '$W/liblepton_ndk_auxv.so' >/dev/null"
        docker exec lepton-runner sh -c "install -m644 '$W/liblepton_ndk_auxv.so' '$D/bin/liblepton_ndk_auxv.so' && cp '$W/ndk_auxv.c' '$D/ndk_auxv.c'"
    done
    echo "ndk shim rebuilt and installed into stages"
else
    echo 'WARN: no clang in runner; NDK shim left as the bundle default (tracked ndk_auxv.c fix not applied)' >&2
fi
echo pushed
