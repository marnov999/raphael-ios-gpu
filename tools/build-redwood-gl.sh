#!/bin/bash
# build-redwood-gl.sh -> out/userland/libredwood-gl.dylib: davinci's libredwood-gl (davinci-ios/gpu/hackios-port
# eagl.c + redwood_gl_egl.c, built as devtools/gl_iter.sh does) with userland/redwood-gl/eagl-raphael.patch:
# CoreAnimation's per-frame new full-screen surface cleared by the GPU instead of copied by the CPU, and an
# unchanged re-attached one kept (2026-11-03).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=/home/marnov/xmiphones/davinci-ios/gpu/hackios-port
CLANG=/home/marnov/xmiphones/kbuild/proton-clang/bin/clang; LDID=/home/marnov/.local/bin/ldid
SDK=/home/marnov/xmiphones/davinci-ios/gpu/userland/mesa/sdk/repo/iPhoneOS16.5.sdk
MESA=/home/marnov/xmiphones/davinci-ios/gpu/userland/mesa
MKEAGL=/home/marnov/xmiphones/hackios-ref/hackios-xnu-userland/userland/mkeagl.py
SLOTS=/home/marnov/xmiphones/hackios-ref/hackios-xnu-userland/userland/src/eagl_slots.txt
W=out/redwood-gl; rm -rf "$W"; mkdir -p "$W/obj" out/userland
cp "$PORT"/eagl.c "$PORT"/redwood_gl_egl.c "$W"/; cp "$PORT"/*.h "$W"/ 2>/dev/null || true; cp "$PORT/obj/exported-gl.txt" "$W/obj/"
patch -s -d "$W" -p1 < userland/redwood-gl/eagl-raphael.patch
export PATH=/home/marnov/xmiphones/kbuild/proton-clang/bin:$PATH
python3 "$MKEAGL" "$SLOTS" "$MESA/src-mesa/src/mapi/glapi/registry/gl.xml" "$W/obj/exported-gl.txt" "$W/eagl.c" > "$W/obj/eagl_gen.h"
"$CLANG" -target arm64-apple-ios16.0 -O2 -isysroot "$SDK" -I"$W/obj" -I"$W" -I"$MESA/src-mesa/include" -fuse-ld=lld -dynamiclib \
	-install_name /usr/local/lib/libredwood-gl.dylib -o out/userland/libredwood-gl.dylib "$W/eagl.c" "$W/redwood_gl_egl.c" userland/redwood-gl/cahook.c userland/redwood-gl/cahook.S \
	"$MESA/gltest/libEGL.1.dylib" "$MESA/gltest/libGLESv2.2.dylib" -framework CoreFoundation -framework IOKit -framework IOSurface \
	-lobjc -Wl,-rpath,@loader_path
"$LDID" -Hsha256 -Cadhoc -S out/userland/libredwood-gl.dylib
echo "built out/userland/libredwood-gl.dylib ($(sha256sum out/userland/libredwood-gl.dylib | cut -c1-16))"
