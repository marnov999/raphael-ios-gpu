#!/bin/bash
# bench81.sh TAG: the frame-rate bench (iOS up, unlocked or on the lock screen): unlock, then
#   TAG-home      home screen pages swiped left and right, 3 times each (tools/measure.sh, backboardd)
#   TAG-settings  Settings opened from the home screen and closed again, 3 times
#   TAG-switcher  the app switcher (swipe up and hold), its cards scrolled 3 times right and back, then home
#   TAG-hcr       Hill Climb Racing (home page 2) launched fresh, START, the gas held 10 s (measured from START:
#                 the first seconds of driving hitched); then home and the game killed
# SECTIONS="home settings switcher hcr" (default) picks them.
# Goal (2026-11-03): median 81 fps (12.3 ms) and p99 at 60 fps or better (16.7 ms) in both.
# The touchscreen is best muted (boot-arg sweettouchmute=1 / mdss touch 0): this panel has ghost touches.
set -uo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: bench81.sh TAG}
LOG=${LOG:-out/logs/u4-usb.log}
# the display off (auto-lock): the power button pressed (xnu 0133 kern.sweet_key), then unlocked
if [ "$(tail -c 3000000 "$LOG" | strings | grep -o 'SWEET FB: display o[nf]*' | tail -1)" = "SWEET FB: display off" ]; then
	tools/run.sh /tmp/mdss key 0 | grep -v '^runlog'
	sleep 1
fi
tools/touch.sh "swipe 540 2335 540 500 250"
sleep 2
SECTIONS=${SECTIONS:-home settings switcher hcr}
on() { case " $SECTIONS " in *" $1 "*) return 0;; esac; return 1; }
if on home; then
H=(); for _ in 1 2 3; do H+=("swipe 950 1300 150 1300 250" "sleep 700" "swipe 150 1300 950 1300 250" "sleep 700"); done
timeout 300 tools/measure.sh "$TAG-home" 10 backboardd -- "${H[@]}" 2>&1 | grep -v "^   busiest"
sleep 2
fi
if on settings; then
A=(); for _ in 1 2 3; do A+=("tap 662 1700" "sleep 1500" "swipe 540 2335 540 1100 200" "sleep 1500"); done
timeout 300 tools/measure.sh "$TAG-settings" 12 backboardd -- "${A[@]}" 2>&1 | grep -v "^   busiest"
sleep 2
fi
if on switcher; then
W=("drag 540 2335 540 1900 150 540 1450 400 540 1450 500" "sleep 1500")
for _ in 1 2 3; do W+=("swipe 150 1300 950 1300 250" "sleep 700"); done
for _ in 1 2 3; do W+=("swipe 950 1300 150 1300 250" "sleep 700"); done
W+=("swipe 540 2335 540 1100 200" "sleep 1500")
timeout 300 tools/measure.sh "$TAG-switcher" 13 backboardd -- "${W[@]}" 2>&1 | grep -v "^   busiest"
sleep 2
fi
if on hcr; then
# home page 1 -> 2 (the games), the icon; the menu after ~20 s; START at once and the gas (landscape: panel x ~ up)
tools/touch.sh "swipe 950 1300 150 1300 250" "sleep 1200" "tap 160 550" "sleep 300"
sleep 22
timeout 300 tools/measure.sh "$TAG-hcr" 13 backboardd -- "tap 301 1757" "sleep 300" "swipe 201 2074 203 2074 10000" 2>&1 | grep -v "^   busiest"
tools/touch.sh "swipe 3 1170 700 1170 200" "sleep 1500" "swipe 150 1300 950 1300 250" "sleep 800"
sleep 3
tools/run.sh /tmp/mdss kill "Hill Climb Racing" >/dev/null
fi
