#!/bin/bash
# touch.sh 'cmd line' ['cmd line' ...]: touches on the phone (iOS, USB up) through davinci's hidtouch, which
# sends them as the real digitizer: "tap X Y", "swipe X1 Y1 X2 Y2 MS", "sleep MS" in panel pixels (1080x2340).
# Mi 9T Pro copy of devtools/touch.sh: pushing hidtouch kills the one running, and a gesture cut short leaves
# a finger "down", so it first waits until the previous sequence has had time to end.
set -euo pipefail
cd "$(dirname "$0")/.."
HIDTOUCH=${HIDTOUCH:-/home/marnov/xmiphones/davinci-ios/gpu/userland/metal/hidtouch}
END=/tmp/raphael_touch_busy_until
now=$(date +%s%N)
if [ -f $END ] && [ "$(cat $END)" -gt "$now" ]; then
	sleep "$(python3 -c "print(($(cat $END) - $now) / 1e9)")"
fi
ms=1000
for c in "$@"; do
	read -r w a b x y d <<< "$c"
	case "$w" in
	swipe) ms=$((ms + ${d:-0} + 120));;
	sleep) ms=$((ms + a + 50));;
	tap) ms=$((ms + 200));;
	esac
done
echo $(( $(date +%s%N) + ms * 1000000 )) > $END
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$@" > "$tmp"
python3 -I tools/push_file.py "$tmp" /tmp/touch_cmd 0644 >/dev/null
python3 -I tools/push_file.py "$HIDTOUCH" /tmp/hidtouch 0755 >/dev/null
