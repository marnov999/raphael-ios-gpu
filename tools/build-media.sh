#!/bin/bash
# build-media.sh -> out/userland/{libsweet-media.dylib,sweet_media_shim}: davinci's mediaserverd library
# (davinci-ios/camera/userland, its build.sh) with userland/media/inject_media-raphael.patch -- CMCapture's
# capture servers started although raphael has no camera, so AVCaptureDevice listings answer (Geometry Dash
# hung on a black screen in +[AVCaptureFigAudioDevice _devices], 2026-11-03).
set -euo pipefail
cd "$(dirname "$0")/.."
W=out/media; rm -rf "$W"; mkdir -p out/userland
cp -r /home/marnov/xmiphones/davinci-ios/camera/userland "$W"
patch -s -d "$W" -p1 < userland/media/inject_media-raphael.patch
sed -i 's|^ABI=.*|ABI=/nonexistent|' "$W/build.sh"     # (raphael has no camera kernel to compare with)
sh "$W/build.sh" >/dev/null
cp "$W/libsweet-media.dylib" "$W/sweet_media_shim" out/userland/
sha256sum out/userland/libsweet-media.dylib out/userland/sweet_media_shim | cut -c1-16
