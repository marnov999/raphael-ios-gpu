#!/bin/bash
# bench81.sh TAG: the frame-rate bench (iOS up, unlocked or on the lock screen): unlock, then
#   TAG-home      home screen pages swiped left and right, 3 times each (tools/measure.sh, backboardd)
#   TAG-settings  Settings opened from the home screen and closed again, 3 times
# Goal (2026-11-03): median 81 fps (12.3 ms) and p99 at 60 fps or better (16.7 ms) in both.
# The touchscreen is best muted (boot-arg sweettouchmute=1 / mdss touch 0): this panel has ghost touches.
set -uo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: bench81.sh TAG}
tools/touch.sh "swipe 540 2335 540 500 250"
sleep 2
H=(); for _ in 1 2 3; do H+=("swipe 950 1300 150 1300 250" "sleep 700" "swipe 150 1300 950 1300 250" "sleep 700"); done
timeout 300 tools/measure.sh "$TAG-home" 10 backboardd -- "${H[@]}" 2>&1 | head -5
sleep 2
A=(); for _ in 1 2 3; do A+=("tap 662 1700" "sleep 1500" "swipe 540 2335 540 1100 200" "sleep 1500"); done
timeout 300 tools/measure.sh "$TAG-settings" 12 backboardd -- "${A[@]}" 2>&1 | head -5
