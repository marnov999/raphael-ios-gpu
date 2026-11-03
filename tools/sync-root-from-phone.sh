#!/bin/bash
# sync-root-from-phone.sh IMAGE [SERIAL]: bring the local iOS root image (tools/build-root.sh) up to what is
# on raphael's iosdata now, pulling only the 512 MiB chunks that differ (sha256 compared on both sides), so the
# phone's iOS state (first boot done, settings) can be patched locally and written back with
# tools/write-root.sh --changed. Reads the phone only. The image is updated in place and kept sparse.
# Run from rooted MIUI, iOS not running (iosdata unmounted). Chunk layout as write-root.sh.
set -euo pipefail
IMG=${1:?usage: sync-root-from-phone.sh IMAGE [SERIAL]} SERIAL=${2:-53d545e6}
ADB="${ADB:-/home/marnov/xmiphones/platform-tools/adb} -s $SERIAL"
PART=/dev/block/by-name/iosdata
EXPECT=26843545600
BS=4194304 CHUNK=128
TMP=/data/local/tmp/iosroot.pull
HOSTTMP=$(mktemp)
trap 'rm -f "$HOSTTMP"' EXIT
su_() { $ADB shell "su -c '$1'" | tr -d '\r'; }
size=$(stat -c %s "$IMG")
[ "$($ADB shell getprop ro.product.device | tr -d '\r')" = raphael ] || { echo "not raphael" >&2; exit 1; }
[ "$(su_ "blockdev --getsize64 $PART")" = "$EXPECT" ] || { echo "iosdata is not $EXPECT bytes" >&2; exit 1; }
dev=$(su_ "readlink -f $PART")
! $ADB shell "grep -q '^$dev ' /proc/mounts" || { echo "$dev is mounted" >&2; exit 1; }
blocks=$((size / BS)) n=$(( (size / BS + CHUNK - 1) / CHUNK ))
pulled=0
for ((i = 0; i < n; i++)); do
	seek=$((i * CHUNK)) cnt=$CHUNK
	[ $((seek + cnt)) -le $blocks ] || cnt=$((blocks - seek))
	have=$(dd if="$IMG" bs=$BS skip=$seek count=$cnt status=none | sha256sum | cut -d' ' -f1)
	phone=$(su_ "dd if=$PART bs=$BS skip=$seek count=$cnt 2>/dev/null | sha256sum" | cut -d' ' -f1)
	if [ "$have" = "$phone" ]; then
		printf 'chunk %2d/%d same\n' $((i + 1)) "$n"
		continue
	fi
	su_ "dd if=$PART of=$TMP bs=$BS skip=$seek count=$cnt 2>/dev/null" >/dev/null
	$ADB pull "$TMP" "$HOSTTMP" >/dev/null
	su_ "rm $TMP" >/dev/null
	[ "$(sha256sum "$HOSTTMP" | cut -d' ' -f1)" = "$phone" ] || { echo "chunk $i: pulled copy does not match the phone" >&2; exit 1; }
	dd if="$HOSTTMP" of="$IMG" bs=$BS seek=$seek count=$cnt conv=notrunc,sparse status=none
	pulled=$((pulled + 1))
	printf 'chunk %2d/%d PULLED\n' $((i + 1)) "$n"
done
echo "SYNC OK: $pulled of $n chunks pulled"
