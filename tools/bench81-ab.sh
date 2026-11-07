#!/bin/bash
# bench81-ab.sh TAG CYCLES "NAME:sysctl=v,sysctl=v" ...: settings compared within one boot, rounds interleaved
# (boot-to-boot differences were as large as the effects measured): each cycle runs one tools/bench81.sh round
# per setting (sysctls set with mdss sysctlw first); at the end, per setting, tools/analysis/skips.py's totals
# and tools/analysis/frames.py's table (how long frames stayed up). A "/path=value" item writes that file on the
# phone instead, and SpringBoard is restarted (killed, launchd starts it again) to read it.
set -uo pipefail
cd "$(dirname "$0")/.."
TAG=$1; N=$2; shift 2
S=/tmp/claude-1000/-home-marnov-xmiphones/9c49bc3f-61eb-47a2-b259-56d8036445a1/scratchpad
G=out/logs/gles-5151.log
for c in $(seq 1 "$N"); do
	for spec in "$@"; do
		name=${spec%%:*}; sets=${spec#*:}
		respring=0
		for kv in ${sets//,/ }; do
			if [ "${kv:0:1}" = / ]; then
				f=$(mktemp); printf '%s' "${kv#*=}" > "$f"
				python3 -I tools/push_file.py "$f" "${kv%%=*}" 0644 >/dev/null; rm -f "$f"; respring=1
			else
				tools/run.sh /tmp/mdss sysctlw "${kv%%=*}" "${kv#*=}" >/dev/null
			fi
		done
		if [ $respring = 1 ]; then tools/run.sh /tmp/mdss kill SpringBoard >/dev/null; sleep 25; fi
		gm=$(stat -c %s $G)
		tools/bench81.sh "$TAG-$name-c$c" >/dev/null 2>&1
		tail -c +$((gm + 1)) $G | strings > "$S/sb_$TAG-$name-c$c.txt"
	done
done
for spec in "$@"; do
	name=${spec%%:*}
	for t in home settings; do
		for c in $(seq 1 "$N"); do
			python3 tools/analysis/skips.py "$S/prof_$TAG-$name-c$c-$t.txt" "$S/sb_$TAG-$name-c$c.txt" | grep SUMMARY
		done | awk -v n="$name" -v t=$t '{f+=$3; l+=$5; s+=$7; k+=$9; c+=$11} END{printf "%-10s %-8s %5d frames: visible %3d (%.2f%%: late %d, server %d, no link %d); still tails %d\n", n, t, f, l+s+k, 100*(l+s+k)/f, l, s, k, c}'
	done
done
for spec in "$@"; do
	name=${spec%%:*}; O=$S/refreshes_$TAG-$name.txt; : > "$O"
	for t in home settings; do python3 -I tools/analysis/ios-refreshes.py $t "$S"/prof_$TAG-$name-c*-$t.txt >> "$O"; done
	echo "== $name"; python3 -I tools/analysis/frames.py refreshes "$O" | grep -v "first 0.6"
done
