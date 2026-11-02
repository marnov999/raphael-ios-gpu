#!/bin/bash
# write-root.sh IMAGE [SERIAL]: write the iOS root image (tools/build-root.sh) into raphael's iosdata
# partition from rooted MIUI, then check it. gzip on both ends: the image is mostly zeros and the phone's
# USB is 2.0. Refuses anything but a raphael with an unmounted 25 GiB iosdata and an image that leaves
# the last 8 MiB free (the kernel's log ring).
set -euo pipefail
IMG=${1:?usage: write-root.sh IMAGE [SERIAL]} SERIAL=${2:-53d545e6}
ADB="${ADB:-/home/marnov/xmiphones/platform-tools/adb} -s $SERIAL"
PART=/dev/block/by-name/iosdata
EXPECT=26843545600			# 25 GiB, tools/gpt-split.py
size=$(stat -c %s "$IMG")
[ "$($ADB shell getprop ro.product.device | tr -d '\r')" = raphael ] || { echo "not raphael" >&2; exit 1; }
psize=$($ADB shell "su -c 'blockdev --getsize64 $PART'" | tr -d '\r')
[ "$psize" = "$EXPECT" ] || { echo "iosdata is $psize bytes, expected $EXPECT" >&2; exit 1; }
[ "$size" -le $((EXPECT - 8 * 1024 * 1024)) ] || { echo "image too big for iosdata minus the log ring" >&2; exit 1; }
dev=$($ADB shell "su -c 'readlink -f $PART'" | tr -d '\r')
! $ADB shell "grep -q '^$dev ' /proc/mounts" || { echo "$dev is mounted" >&2; exit 1; }
echo "writing $IMG ($size bytes) to $PART ($dev)"
gzip -1 -c "$IMG" | $ADB exec-in "su -c 'gzip -dc | dd of=$PART bs=4194304 conv=notrunc 2>/dev/null; sync'"
want=$(sha256sum "$IMG" | cut -d' ' -f1)
got=$($ADB shell "su -c 'head -c $size $PART | sha256sum'" | cut -d' ' -f1)
echo "image  $want"
echo "phone  $got"
[ "$want" = "$got" ] && echo "WRITE OK" || { echo "MISMATCH" >&2; exit 1; }
