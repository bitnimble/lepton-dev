#!/bin/bash
# Host-side: dump full logcat of a context into the runner and show crash/app-relevant lines.
# Usage: diag.sh <ctx> <package> [extra-grep-regex]
CTX="$1"; PKG="$2"; EXTRA="${3:-^$}"
docker exec lepton-runner bash -c "
C=lepton-$CTX
D=/var/lib/containers/lepton/run/$CTX.logcat.txt
podman exec \$C /system/bin/logcat -d -b all >| \$D 2>&1
echo \"pid: \$(podman exec \$C /system/bin/pidof $PKG)\"
echo '--- crash buffer'
podman exec \$C /system/bin/logcat -d -b crash | grep -E 'Cmdline|Abort message|signal [0-9]|backtrace:|#0[0-5] ' | tail -20
echo '--- app process lifecycle'
grep -E 'ActivityManager.*($PKG)|Process $PKG|has died|Force finishing|ANR in' \$D | tail -12
echo '--- app errors'
grep -E ' (E|F) ' \$D | grep -iE 'unity|il2cpp|ndk_translation|libc  |native_bridge|$EXTRA' | tail -25
"
