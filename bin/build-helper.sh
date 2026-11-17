#!/bin/bash
# Host-side: builds helper/ (the Android screens the add-on shows, e.g. the Google setup spinner) into
# addon/lepton-helper.apk with its Gradle wrapper. Needs JDK 17+ and the Android SDK (ANDROID_HOME, or sdk.dir in
# helper/local.properties). Signs with ~/.android/debug.keystore, which Gradle creates if missing.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
"$R/helper/gradlew" -p "$R/helper" --quiet assembleRelease
cp "$R/helper/build/outputs/apk/release/lepton-helper-release.apk" "$R/addon/lepton-helper.apk"
echo "built addon/lepton-helper.apk"
