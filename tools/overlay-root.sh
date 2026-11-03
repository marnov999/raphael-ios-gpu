#!/bin/bash
# overlay-root.sh: davinci's GPU userland (tools/sweet-root-overlay.py: Mesa, libredwood-gl, SweetGLES,
# RedwoodMetal, launchd shims, flags, dyld-cache patches) put onto the raphael root image, in a privileged
# ubuntu:22.04 container as build-root.sh is made (Linux mounts the journaled HFS+ only with "force", so the
# journal must be empty first: tools/hfs-journal.py). Then fsck.
#
# Host:  docker run --rm --privileged \
#          -v /home/marnov/xmiphones/raphael-ios-gpu:/src:ro \
#          -v /home/marnov/xmiphones:/base:ro \
#          -v /home/marnov/xmiphones/raphael-ios-gpu/out/root:/work \
#          ubuntu:22.04 bash /src/tools/overlay-root.sh [overlay args...]
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
IMG=/work/ios16-root-raphael.img
apt-get update -q >/dev/null
apt-get install -y -q hfsprogs python3 >/dev/null
# A root iOS has run on: its hard-link counts (iOS's own bookkeeping) are all Linux's fsck_hfs finds wrong;
# anything else and the image is not mounted.
check() {
	fsck.hfsplus -fn "$IMG" > /tmp/fsck.txt 2>&1 && return
	cat /tmp/fsck.txt
	if grep -v "Incorrect number of file hard links" /tmp/fsck.txt | grep -qiE "incorrect|invalid|missing|overlapped|bad|error"; then
		echo "fsck $1 the overlay found problems" >&2
		exit 1
	fi
	echo "(only the hard-link count: going on)"
}
check before
mkdir -p /mnt/iosroot
mount -t hfsplus -o loop,force "$IMG" /mnt/iosroot
grep -q " /mnt/iosroot hfsplus rw" /proc/mounts || { echo "mounted read-only (not cleanly unmounted? tools/hfs-journal-replay.py --apply)" >&2; umount /mnt/iosroot; exit 1; }
python3 -I /src/tools/sweet-root-overlay.py --base /base "$@" /mnt/iosroot || { umount /mnt/iosroot; exit 1; }
sync
umount /mnt/iosroot
check after
echo OVERLAY_DONE
