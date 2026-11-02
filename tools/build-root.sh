#!/bin/bash
# build-root.sh: the iOS 16.7.16 root image for raphael's iosdata, in a privileged ubuntu:22.04 container
# (hfsprogs is gone from Debian 12; loop + FUSE mounts need --privileged). Same recipe as davinci's
# davinci-ios/build_root.sh: apfs-fuse from source, tools/mkiosroot.sh (OS + SystemOS/AppOS cryptexes into
# case-sensitive HFS+), fsck, tools/sweet-root-tweaks.py. No sparse image: tools/write-root.sh streams the
# raw image over adb. Size = iosdata (25 GiB) minus 8 MiB: the kernel keeps its log ring at the partition's
# end (0047, 4 MiB + 4 KiB).
#
# Host:  docker run -d --name raphael_root --privileged \
#          -v /home/marnov/xmiphones/raphael-ios-gpu:/src:ro \
#          -v /home/marnov/xmiphones/davinci-ios/ipsw:/ipsw:ro \
#          -v /home/marnov/xmiphones/raphael-ios-gpu/out/root:/work \
#          ubuntu:22.04 bash /src/tools/build-root.sh
#        docker logs -f raphael_root          (ends with ROOTBUILD_DONE)
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
SIZE=${SIZE:-26835156992}
OUT=/work/ios16-root-raphael.img
echo "=== [1/4] deps ==="
apt-get update -q
apt-get install -y -q build-essential cmake git libfuse3-dev zlib1g-dev libbz2-dev rsync hfsprogs fuse3 \
	python3 pkg-config
printf '#!/bin/sh\nexec "$@"\n' > /usr/local/bin/sudo
chmod +x /usr/local/bin/sudo
echo "=== [2/4] apfs-fuse ==="
cd /opt
git clone -q --recursive https://github.com/sgan81/apfs-fuse
mkdir -p apfs-fuse/build && cd apfs-fuse/build
cmake .. -DCMAKE_BUILD_TYPE=Release >/dev/null
make -j"$(nproc)" >/dev/null
find /opt/apfs-fuse -name apfs-fuse -type f -exec cp {} /usr/local/bin/ \;
echo "apfs-fuse: $(command -v apfs-fuse)"
echo "=== [3/4] mkiosroot ($SIZE bytes) ==="
bash /src/tools/mkiosroot.sh /ipsw/087-86698-044.dmg /ipsw/087-86593-047.dmg /ipsw/087-86715-047.dmg "$OUT" "$SIZE"
echo "=== [4/4] fsck + tweaks ==="
fsck.hfsplus -fy "$OUT" || true
mkdir -p /mnt/iosroot
mount -t hfsplus -o loop,force "$OUT" /mnt/iosroot
python3 /src/tools/sweet-root-tweaks.py /mnt/iosroot
df -h /mnt/iosroot
sync
umount /mnt/iosroot
fsck.hfsplus -fn "$OUT"
chown 1000:1000 "$OUT"
ls -la "$OUT"
echo "ROOTBUILD_DONE"
