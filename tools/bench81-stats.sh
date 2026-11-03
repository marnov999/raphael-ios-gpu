#!/bin/bash
# bench81-stats.sh TAG [ROUNDS]: tools/bench81.sh ROUNDS times (3) with SpringBoard's frames traced (libcahook:
# /usr/local/gltest/gl_cahook_sb and gl_cahook saying 1), every refresh without a new frame classified by
# tools/analysis/skips.py; per test, over all rounds: frames, and the visible misses (late + server + no link).
set -uo pipefail
cd "$(dirname "$0")/.."
TAG=${1:?usage: bench81-stats.sh TAG [ROUNDS]}; N=${2:-3}
S=/tmp/claude-1000/-home-marnov-xmiphones/9c49bc3f-61eb-47a2-b259-56d8036445a1/scratchpad
G=out/logs/gles-5151.log
for r in $(seq 1 "$N"); do
	gm=$(stat -c %s $G)
	tools/bench81.sh "$TAG-r$r" >/dev/null 2>&1
	tail -c +$((gm + 1)) $G | strings > "$S/sb_$TAG-r$r.txt"
done
for t in home settings; do
	for r in $(seq 1 "$N"); do
		python3 tools/analysis/skips.py "$S/prof_$TAG-r$r-$t.txt" "$S/sb_$TAG-r$r.txt" | grep SUMMARY
	done | awk -v t=$t '{f+=$3; l+=$5; s+=$7; n+=$9; c+=$11} END{printf "%s: %d frames: visible misses %d (%.2f%%: late %d, server %d, no link %d); still tails %d\n", t, f, l+s+n, 100*(l+s+n)/f, l, s, n, c}'
done
