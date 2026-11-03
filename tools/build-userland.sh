#!/bin/bash
# build-userland.sh: raphael's own on-device helpers (userland/*.c) -> out/userland/, ad-hoc signed as
# every shim of the project (geekbench/tools/build.sh's toolchain: proton-clang 13 + iPhoneOS16.5.sdk).
set -euo pipefail
cd "$(dirname "$0")/.."
CLANG=/home/marnov/xmiphones/kbuild/proton-clang/bin/clang
LDID=/home/marnov/.local/bin/ldid
SDK=/home/marnov/xmiphones/davinci-ios/gpu/userland/mesa/sdk/repo/iPhoneOS16.5.sdk
mkdir -p out/userland
for src in userland/*.c; do
	name=$(basename "$src" .c)
	"$CLANG" -target arm64-apple-ios16.0 -O2 -isysroot "$SDK" -fuse-ld=lld -o "out/userland/$name" "$src" \
		-framework CoreFoundation -framework IOSurface
	"$LDID" -S "out/userland/$name"
	echo "built out/userland/$name ($(sha256sum "out/userland/$name" | cut -c1-16))"
done
