#!/bin/bash
# build-cahook.sh: userland/redwood-gl/cahook.{c,S} as libcahook.dylib (SpringBoard's hooks, put in by sweet_shim with
# /usr/local/gltest/gl_cahook_sb saying 1; frame rate requests scaled by /usr/local/gltest/gl_sb_fps) -> out/userland
set -euo pipefail
cd "$(dirname "$0")/.."
CLANG=/home/marnov/xmiphones/kbuild/proton-clang/bin/clang; LDID=/home/marnov/.local/bin/ldid
SDK=/home/marnov/xmiphones/davinci-ios/gpu/userland/mesa/sdk/repo/iPhoneOS16.5.sdk
mkdir -p out/userland
"$CLANG" -target arm64-apple-ios16.0 -O2 -isysroot "$SDK" -fuse-ld=lld -dynamiclib -DCAHOOK_STANDALONE \
	-install_name /usr/local/lib/libcahook.dylib -o out/userland/libcahook.dylib userland/redwood-gl/cahook.c userland/redwood-gl/cahook.S
"$LDID" -Hsha256 -Cadhoc -S out/userland/libcahook.dylib
echo "built out/userland/libcahook.dylib ($(sha256sum out/userland/libcahook.dylib | cut -c1-16))"
