#!/bin/bash
# build-atouch.sh: userland/android/atouch.c -> out/userland/atouch (static aarch64 Linux, no libc: runs on MIUI)
set -euo pipefail
cd "$(dirname "$0")/.."
CC=${CC:-/home/marnov/xmiphones/kbuild/proton-clang/bin/clang}
mkdir -p out/userland
"$CC" --target=aarch64-linux-gnu -O2 -Wall -Wextra -ffreestanding -fno-builtin -fno-stack-protector -fno-pic \
	-nostdlib -static -fuse-ld=lld -Wl,-e,_start -o out/userland/atouch userland/android/atouch.c
echo out/userland/atouch
