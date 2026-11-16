#!/bin/bash
# Host-side: builds data/mantis-buddy/host.apk.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/android/sdk}"
BT="$SDK/build-tools/36.0.0"
JAR="$SDK/platforms/android-36/android.jar"
SRC="$R/mantis-buddy/host"
OUT="$R/data/mantis-buddy"
W="$OUT/host-work"
rm -rf "$W"
mkdir -p "$W/classes" "$W/dex"
javac --release 17 -classpath "$JAR" -d "$W/classes" "$SRC"/src/lepton/mantisbuddy/*.java
"$BT/d8" --min-api 34 --lib "$JAR" --output "$W/dex" "$W"/classes/lepton/mantisbuddy/*.class
"$BT/aapt2" link -o "$W/unsigned.apk" -I "$JAR" --manifest "$SRC/AndroidManifest.xml"
(cd "$W/dex" && zip -q "$W/unsigned.apk" classes.dex)
"$BT/zipalign" -f 4 "$W/unsigned.apk" "$W/aligned.apk"
KEY="$OUT/debug.keystore"
[[ -f "$KEY" ]] || keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias debug \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Lepton debug" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:android --out "$OUT/host.apk" "$W/aligned.apk"
echo "$OUT/host.apk"
