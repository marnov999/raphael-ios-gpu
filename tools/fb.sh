#!/bin/bash
# fb.sh: fastboot for the Mi 9T Pro only. The Mi 9T (davinci) is often connected at the same time, so
# every command names the Pro's serial and first checks that this serial is in fastboot and reports
# product "raphael"; otherwise nothing is sent.
#
#   tools/fb.sh wait                  wait (up to 2 min) for the Pro in fastboot
#   tools/fb.sh boot IMAGE            fastboot boot (RAM only)
#   tools/fb.sh flash-boot IMAGE --yes  write IMAGE to the boot partition (keep the old one for rollback)
#   tools/fb.sh reboot                reboot from fastboot
#   tools/fb.sh getvar NAME
#
# RAPHAEL_SERIAL overrides the serial (53d545e6).
set -euo pipefail
SERIAL=${RAPHAEL_SERIAL:-53d545e6}
FB=${FASTBOOT:-/home/marnov/xmiphones/platform-tools/fastboot}
cmd=${1:?usage: fb.sh wait|boot IMAGE|flash-boot IMAGE --yes|reboot|getvar NAME}

present() { "$FB" devices | awk '{print $1}' | grep -qx "$SERIAL"; }
check() {
	present || { echo "fb.sh: $SERIAL is not in fastboot ($("$FB" devices | awk '{print $1}' | tr '\n' ' '))" >&2; exit 1; }
	local p
	p=$("$FB" -s "$SERIAL" getvar product 2>&1 | sed -n 's/^product: *//p')
	[ "$p" = raphael ] || { echo "fb.sh: $SERIAL reports product '$p', not raphael" >&2; exit 1; }
}

case "$cmd" in
wait)
	for _ in $(seq 1 60); do present && break; sleep 2; done
	check
	echo "$SERIAL (raphael) in fastboot"
	;;
boot)
	img=${2:?image}
	check
	"$FB" -s "$SERIAL" boot "$img"
	;;
flash-boot)
	img=${2:?image}
	[ "${3:-}" = --yes ] || { echo "fb.sh: flash-boot needs --yes (writes the boot partition)" >&2; exit 1; }
	check
	"$FB" -s "$SERIAL" flash boot "$img"
	;;
reboot)
	check
	"$FB" -s "$SERIAL" reboot
	;;
getvar)
	check
	"$FB" -s "$SERIAL" getvar "${2:?name}"
	;;
*)
	echo "fb.sh: unknown command $cmd" >&2
	exit 1
	;;
esac
