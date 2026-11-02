#!/bin/bash
# write-root.sh IMAGE [SERIAL]: write the iOS root image (tools/build-root.sh) into raphael's iosdata
# partition from rooted MIUI, chunk by chunk, each chunk checked on the partition afterwards.
#
# Not a pipe into `su -c dd`: Magisk's su relays stdin so that toybox dd stops after its first 4 MiB
# block and toybox `gzip -dc` writes nothing (2026-11-02: the whole first attempt landed nowhere, which
# only the final sha256 caught). So: `adb push` a chunk to /data/local/tmp, dd it into place from the
# file, compare its sha256 on the partition. All-zero chunks are written from /dev/zero instead of being
# sent. Refuses anything but a raphael with an unmounted 25 GiB iosdata and an image that leaves the last
# 8 MiB free (the kernel's log ring).
set -euo pipefail
IMG=${1:?usage: write-root.sh IMAGE [SERIAL]} SERIAL=${2:-53d545e6}
ADB="${ADB:-/home/marnov/xmiphones/platform-tools/adb} -s $SERIAL"
PART=/dev/block/by-name/iosdata
EXPECT=26843545600			# 25 GiB, tools/gpt-split.py
BS=4194304 CHUNK=128			# 128 x 4 MiB = 512 MiB a chunk
TMP=/data/local/tmp/iosroot.chunk
HOSTTMP=$(mktemp)
trap 'rm -f "$HOSTTMP"' EXIT
su_() { $ADB shell "su -c '$1'" | tr -d '\r'; }
size=$(stat -c %s "$IMG")
[ $((size % BS)) = 0 ] || { echo "image size is not a multiple of 4 MiB" >&2; exit 1; }
[ "$($ADB shell getprop ro.product.device | tr -d '\r')" = raphael ] || { echo "not raphael" >&2; exit 1; }
[ "$(su_ "blockdev --getsize64 $PART")" = "$EXPECT" ] || { echo "iosdata is not $EXPECT bytes" >&2; exit 1; }
[ "$size" -le $((EXPECT - 8 * 1024 * 1024)) ] || { echo "image too big for iosdata minus the log ring" >&2; exit 1; }
dev=$(su_ "readlink -f $PART")
! $ADB shell "grep -q '^$dev ' /proc/mounts" || { echo "$dev is mounted" >&2; exit 1; }
blocks=$((size / BS)) n=$(( (size / BS + CHUNK - 1) / CHUNK ))
echo "writing $IMG ($size bytes, $n chunks of 512 MiB) to $PART ($dev)"
sent=0
for ((i = 0; i < n; i++)); do
	seek=$((i * CHUNK)) cnt=$CHUNK
	[ $((seek + cnt)) -le $blocks ] || cnt=$((blocks - seek))
	dd if="$IMG" of="$HOSTTMP" bs=$BS skip=$seek count=$cnt status=none
	want=$(sha256sum "$HOSTTMP" | cut -d' ' -f1)
	if cmp -s -n $((cnt * BS)) "$HOSTTMP" /dev/zero; then
		su_ "dd if=/dev/zero of=$PART bs=$BS seek=$seek count=$cnt conv=notrunc 2>/dev/null" >/dev/null
		how=zero
	else
		$ADB push "$HOSTTMP" "$TMP" >/dev/null
		su_ "dd if=$TMP of=$PART bs=$BS seek=$seek count=$cnt conv=notrunc 2>/dev/null; rm $TMP" >/dev/null
		how=data sent=$((sent + cnt * BS))
	fi
	got=$(su_ "sync; dd if=$PART bs=$BS skip=$seek count=$cnt 2>/dev/null | sha256sum" | cut -d' ' -f1)
	[ "$got" = "$want" ] || { echo "chunk $i ($how) MISMATCH: image $want phone $got" >&2; exit 1; }
	printf 'chunk %2d/%d %s ok\n' $((i + 1)) "$n" "$how"
done
echo "WRITE OK: $n chunks verified, $((sent / 1048576)) MiB sent"
