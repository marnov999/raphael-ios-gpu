#!/bin/bash
# bench-miui.sh TAG [RUNS]: the frame-rate bench on MIUI (tools/android/bench60-miui.sh), RUNS times (default 3);
# traces to out/logs/miui/TAG-N.txt. Holds the real touchscreen (ghost touches) for the whole bench, then frees it.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: bench-miui.sh TAG [RUNS]} RUNS=${2:-3}
ADB="${ADB:-/home/marnov/xmiphones/platform-tools/adb} -s ${RAPHAEL_SERIAL:-53d545e6}"
mkdir -p out/logs/miui
tools/build-atouch.sh >/dev/null
$ADB push out/userland/atouch /data/local/tmp/atouch >/dev/null
$ADB push tools/android/bench60-miui.sh /data/local/tmp/bench60-miui.sh >/dev/null
$ADB shell su -c "'chmod 755 /data/local/tmp/atouch; pidof atouch >/dev/null || nohup /data/local/tmp/atouch -g \"sleep 7200000\" </dev/null >/dev/null 2>&1 &'" </dev/null
$ADB shell input keyevent KEYCODE_WAKEUP 2>/dev/null || true
for n in $(seq 1 "$RUNS"); do
	$ADB shell su -c "'sh /data/local/tmp/bench60-miui.sh /data/local/tmp/$TAG-$n.txt'"
	$ADB pull "/data/local/tmp/$TAG-$n.txt" "out/logs/miui/$TAG-$n.txt" >/dev/null
	$ADB shell su -c "'rm -f /data/local/tmp/$TAG-$n.txt'"
done
[ "${KEEPGRAB:-0}" = 1 ] || $ADB shell su -c "'pkill -f \"atouch -g\"'" || true
ls -la out/logs/miui/$TAG-*.txt
