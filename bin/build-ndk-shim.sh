#!/bin/bash
# Host-side: builds patches/ndk_auxv.c in lepton-runner and vendors the result as patches/liblepton_ndk_auxv.so.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
source "$R/bin/lib.sh"
put "$R/patches/ndk_auxv.c" "$W/ndk_auxv.c"
runner_exec clang --target=x86_64-linux-android34 -O2 -fPIC -shared -nostdlib -fvisibility=hidden \
    -Wall -Wextra -Werror -Wl,-soname,liblepton_ndk_auxv.so -o "$W/liblepton_ndk_auxv.so" "$W/ndk_auxv.c"
runner_exec bash "$W/stage/compat_tool/liblepton/ndk_auxv/validate.sh" "$W/liblepton_ndk_auxv.so"
pull_file "$W/liblepton_ndk_auxv.so" "$R/patches/liblepton_ndk_auxv.so"
echo "vendored patches/liblepton_ndk_auxv.so"
