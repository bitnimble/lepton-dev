#!/bin/bash
# Host-side: builds an ARM64-flagged test apk (data/mantis-buddy/abitest.apk). The embedded ARM64 .so
# forces primaryCpuAbi=arm64-v8a, so Android forks its process under the NDK translator.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${ANDROID_HOME:-$HOME/android/sdk}"
BT="$SDK/build-tools/36.0.0"
JAR="$SDK/platforms/android-36/android.jar"
SRC="$R/mantis-buddy/abitest"
OUT="$R/data/mantis-buddy"
ARM64_SO="${1:-/tmp/mantis-re/apk/assets/flutter_assets/assets/injection/libbuddy1}"
rm -rf "$OUT/abitest-work"
mkdir -p "$OUT/abitest-work/classes" "$OUT/abitest-work/dex" "$OUT/abitest-work/lib/arm64-v8a"
cp "$ARM64_SO" "$OUT/abitest-work/lib/arm64-v8a/libforce.so"
javac --release 17 -classpath "$JAR" -d "$OUT/abitest-work/classes" "$SRC"/src/lepton/abitest/*.java
"$BT/d8" --min-api 34 --lib "$JAR" --output "$OUT/abitest-work/dex" "$OUT"/abitest-work/classes/lepton/abitest/*.class
"$BT/aapt2" link -o "$OUT/abitest-work/unsigned.apk" -I "$JAR" --manifest "$SRC/AndroidManifest.xml"
(cd "$OUT/abitest-work/dex" && zip -q "$OUT/abitest-work/unsigned.apk" classes.dex)
(cd "$OUT/abitest-work" && zip -q unsigned.apk lib/arm64-v8a/libforce.so)
"$BT/zipalign" -f 4 "$OUT/abitest-work/unsigned.apk" "$OUT/abitest-work/aligned.apk"
KEY="$OUT/debug.keystore"
[[ -f "$KEY" ]] || keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias debug \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Lepton debug" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KEY" --ks-pass pass:android --out "$OUT/abitest.apk" "$OUT/abitest-work/aligned.apk"
echo "$OUT/abitest.apk"
