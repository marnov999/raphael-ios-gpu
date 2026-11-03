#!/bin/bash
# run.sh PROGRAM [ARGS...]: run a program on the phone (iOS, USB gadget up) and print its stdout+stderr.
# davinci's runlog (pushed, it runs itself): /tmp/runlog_args -> /tmp/runlog.txt, up to 60 s.
set -euo pipefail
cd "$(dirname "$0")/.."
RUNLOG=${RUNLOG:-/home/marnov/xmiphones/davinci-ios/gpu/userland/metal/runlog}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo "$*" > "$tmp"
python3 -I tools/push_file.py "$tmp" /tmp/runlog_args 0644 >/dev/null
python3 -I tools/push_file.py "$RUNLOG" /tmp/runlog 0755 >/dev/null
for _ in $(seq 1 70); do
	sleep 1
	if python3 -I tools/read_file.py /tmp/runlog.txt > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
		cat "$tmp"
		exit 0
	fi
done
echo "run.sh: no output from $1 after 70 s" >&2
exit 1
