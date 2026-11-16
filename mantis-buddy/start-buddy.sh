#!/system/bin/sh
# Guest-side, as root: (re)starts the Mantis buddy daemon inside the Android container.
set -eu
M=/data/local/tmp/mantis
TARGET=com.android.DeviceAsWebcam

BUNDLE=""
[ -r "$M/active" ] && read -r BUNDLE <"$M/active"
if [ ! -f "$M/bundles/$BUNDLE/mantis.dex" ]; then
    for dir in $(ls -t "$M/bundles"); do
        case "$dir" in tmp-* | bad-*) continue ;; esac
        BUNDLE=$dir
        break
    done
fi
[ -f "$M/bundles/$BUNDLE/mantis.dex" ] || { echo "no Mantis bundle in $M/bundles; activate Mantis once first" >&2; exit 1; }

[ -c /dev/uinput ] && chmod 666 /dev/uinput

# podman exec lacks init's service environment; without BOOTCLASSPATH, `am instrument` (an app_process) exits silently
for kv in $(tr '\0' '\n' </proc/"$(pidof -s adbd)"/environ); do
    case "$kv" in ANDROID_* | *CLASSPATH=*) export "$kv" ;; esac
done

am force-stop "$TARGET"
rm -f "$M/control/started"
am instrument --no-hidden-api-checks --abi arm64-v8a \
    -e bundle "$M/bundles/$BUNDLE" -e operation "$(date +%s)-lepton" \
    lepton.mantisbuddy/.BuddyHost </dev/null

i=0
while [ $i -lt 50 ]; do
    [ -s "$M/control/started" ] && { echo "buddy started: $BUNDLE"; exit 0; }
    sleep 0.2
    i=$((i + 1))
done
echo "buddy didn't report started; see logcat -s LeptonMantisBuddy" >&2
exit 1
