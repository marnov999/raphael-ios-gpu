#!/bin/bash
# gametest.sh BUNDLE-ID EXE [SECS]: open an app on the phone (iOS, USB up) through FrontBoard (geekbench's
# launchapp: /tmp/launch_args -> /tmp/launchapp.txt), wait SECS (40), then report whether EXE still runs
# (mdss top), its newest crash report and a screenshot in out/games/EXE.png. The app is killed afterwards
# unless KEEP=1. Its stdout+stderr (FrontBoard debug options) go to /tmp/game-EXE.log on the phone and
# out/games/EXE.log here; ENV="K=V K2=V2" sets environment variables for it.
set -uo pipefail
cd "$(dirname "$0")/.."
B=${1:?bundle id}; EXE=${2:?executable name}; SECS=${3:-40}
LAUNCHAPP=${LAUNCHAPP:-out/games/launchapp}   # userland/launchapp/launchapp.m, signed with userland/launchapp.ents
mkdir -p out/games
LOG=${LOG:-$(ls -t out/logs/*-usb.log 2>/dev/null | head -1)}
# FrontBoard opens nothing while locked: the screen woken if off (power key), then the swipe up that unlocks
if [ "$(tail -c 3000000 "$LOG" | strings | grep -o 'SWEET FB: display o[nf]*' | tail -1)" = "SWEET FB: display off" ]; then
	tools/run.sh /tmp/mdss key 0 >/dev/null; sleep 1
fi
tools/touch.sh "swipe 540 2335 540 500 250" >/dev/null; sleep 2
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
LOGN=$(echo "$EXE" | tr -c 'A-Za-z0-9\n' _)
{ printf '%s out=/tmp/game-%s.log' "$B" "$LOGN"; for e in ${ENV:-}; do printf ' env=%s' "$e"; done; echo; } > "$tmp"
python3 -I tools/push_file.py "$tmp" /tmp/launch_args 0644 >/dev/null
python3 -I tools/push_file.py "$LAUNCHAPP" /tmp/launchapp 0755 >/dev/null
sleep 3
echo "== launchapp"; python3 -I tools/read_file.py /tmp/launchapp.txt 2>/dev/null | tail -4
sleep "$SECS"
echo "== running?"; tools/run.sh /tmp/mdss top 2 2>&1 | grep -F -- "$EXE" || echo "$EXE: not running"
echo "== crash reports"; tools/rfind.sh /private/var/mobile/Library/Logs/CrashReporter "$EXE" 2>/dev/null | sort -n | tail -3
python3 -I tools/read_file.py "/tmp/game-$LOGN.log" > "out/games/$LOGN.log" 2>/dev/null
echo "== output ($(wc -l < "out/games/$LOGN.log") lines, out/games/$LOGN.log)"; tail -${TAILN:-15} "out/games/$LOGN.log"
python3 -I tools/screencap.py "out/games/$EXE.png" >/dev/null 2>&1 && echo "== screenshot out/games/$EXE.png"
[ "${KEEP:-0}" = 1 ] || tools/run.sh /tmp/mdss kill "$EXE" >/dev/null 2>&1
exit 0
