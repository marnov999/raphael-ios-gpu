#!/bin/bash
# mkiosimg.sh NAME KERNEL [extra boot-args...] -> out/raphael-ios-NAME.img (for `fastboot boot`)
#
# The raphael counterpart of davinci's mkiosimg.sh: the shim as kernel, the xnu payload (kernel + ADT +
# boot-args, tools/mkpayload.py) as ramdisk, the stock SoC DTBs in a separate section. raphael's ABL
# accepts only boot header v2 with the DTB at dtb_offset 0x1f00000; a v1 image (DTB appended to the
# kernel) is silently not run.
#
# Environment:
#   ROOT=name    partition for ufsroot= (default rawdump). The kernel keeps its 4 MiB log ring at the end
#                of that partition. Use userdata/iosdata only once it holds the iOS root.
#   CONSOLE=1    keep the kernel console on screen after the GUI starts (sweetfb_noconsole=0)
#   CPUS=n       cpus= (default 8). Not as an extra boot-arg: xnu takes the first cpus= it finds.
#   HZ=n         sweetfb_hz= (default 30; davinci runs 60). Not as an extra boot-arg, as CPUS.
#   ADT=path     device tree (default out/raphael.adt, from tools/mkadt.py OUT --raphael --highmem)
#   DTB=path     stock SoC DTBs (default dtb/raphael-stock.dtb, from tools/stock-dtbs.py)
#   SHIM=path    shim Image (default shim/out-clang/Image, from shim/build-clang.sh)
#   DEFAULT=miui the boot menu's 10 s countdown boots MIUI instead of iOS (for the flashed image while there
#                is no iOS root); needs MIUI=
#   FLASH=1      an image for the boot partition: without "sweetnocharger", so a charger plugged into a
#                switched-off phone starts MIUI's charging screen. Test images for `fastboot boot` carry
#                it, since ABL still says charger after the phone was last switched on by the charger.
#   MIUI=dir     also pack MIUI's kernel behind the payload (dir from tools/unpack-miui-boot.py: Image,
#                ramdisk.cpio, cmdline.txt): the boot menu's "Boot MIUI" and off-mode charging (shim/linux.c)
set -euo pipefail
cd "$(dirname "$0")/.."
NAME=${1:?usage: mkiosimg.sh NAME KERNEL [boot-args...]} K=${2:?kernel}; shift 2
ROOT=${ROOT:-rawdump}
ADT=${ADT:-out/raphael.adt} DTB=${DTB:-dtb/raphael-stock.dtb} SHIM=${SHIM:-shim/out-clang/Image}
case "$ROOT" in userdata) [ "${ALLOW_USERDATA:-0}" = 1 ] || {
	echo "refusing ufsroot=userdata: it is MIUI's data until the iOS root is installed (ALLOW_USERDATA=1)" >&2
	exit 1; };; esac
NOCON=1; [ "${CONSOLE:-0}" = 1 ] && NOCON=0
IMGCMD="console=null"
[ "${FLASH:-0}" = 1 ] || IMGCMD="$IMGCMD sweetnocharger"
case "${DEFAULT:-ios}" in ios) ;; miui) [ -n "${MIUI:-}" ] || { echo "DEFAULT=miui needs MIUI=" >&2; exit 1; }
	IMGCMD="$IMGCMD sweetdefault=miui";; *) echo "DEFAULT is ios or miui" >&2; exit 1;; esac
CMDLINE="rd=ufsroot0 ufsroot=$ROOT debug=0xc serial=3 cpus=${CPUS:-8} keepsyms=1 -enable_kprintf_spam -noprogress unentitled_ios_sim_launch=1 ignition_level=1 wdt_test=no_user_checkin ufsrw=1 rootrw=1 launchd_unsecure_cache=1 wdt=-1 sweetfb_noconsole=$NOCON sweetfb_hz=${HZ:-30} $*"
for f in "$K" "$ADT" "$DTB" "$SHIM"; do [ -s "$f" ] || { echo "missing $f" >&2; exit 1; }; done
mkdir -p out
python3 tools/mkpayload.py "$K" "$ADT" "out/${NAME}_payload.bin" --cmdline "$CMDLINE" >/dev/null
RD="out/${NAME}_payload.bin"
if [ -n "${MIUI:-}" ]; then
	python3 tools/mkcombo.py "$RD" "$MIUI/Image" "$MIUI/ramdisk.cpio" "$MIUI/cmdline.txt" "out/${NAME}_combo.bin" >/dev/null
	RD="out/${NAME}_combo.bin"
fi
python3 tools/mkbootimg.py --header_version 2 --kernel "$SHIM" --ramdisk "$RD" \
	--dtb "$DTB" --base 0 --kernel_offset 0x8000 --ramdisk_offset 0x1000000 --tags_offset 0x100 \
	--dtb_offset 0x1f00000 --pagesize 4096 --os_version 11.0.0 --os_patch_level 2021-10 \
	--cmdline "$IMGCMD" -o "out/raphael-ios-$NAME.img"
echo "out/raphael-ios-$NAME.img [$IMGCMD]: $CMDLINE"
