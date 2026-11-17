#!/bin/bash
# Host-side: builds helper/ (the Android screens the add-on shows, e.g. the Google setup spinner) into
# addon/lepton-helper.apk. Needs JDK 17+ and the Android SDK (build-tools 36, platform 36): ANDROID_HOME, default
# ~/android/sdk. Signs with ~/.android/debug.keystore, creating it if missing.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/android/sdk}"
BT="$SDK/build-tools/36.0.0"
JAR="$SDK/platforms/android-36/android.jar"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
KEY="$HOME/.android/debug.keystore"

mkdir -p "$W/classes" "$W/dex"
find "$R/helper/src" -name '*.java' >"$W/sources"
javac --release 17 -Xlint:all,-options -Werror -classpath "$JAR" -d "$W/classes" @"$W/sources"
mapfile -t classes < <(find "$W/classes" -name '*.class')
"$BT/d8" --min-api 30 --lib "$JAR" --output "$W/dex" "${classes[@]}"
"$BT/aapt2" link -o "$W/unsigned.apk" -I "$JAR" --manifest "$R/helper/AndroidManifest.xml"
(cd "$W/dex" && zip -q "$W/unsigned.apk" classes.dex)
"$BT/zipalign" -f 4 "$W/unsigned.apk" "$W/aligned.apk"
if [[ ! -f "$KEY" ]]; then
    mkdir -p "$(dirname "$KEY")"
    keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias androiddebugkey \
        -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:android --out "$R/addon/lepton-helper.apk" "$W/aligned.apk"
rm -f "$R/addon/lepton-helper.apk.idsig"
echo "built addon/lepton-helper.apk"
