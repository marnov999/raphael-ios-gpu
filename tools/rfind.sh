#!/bin/bash
# rfind.sh DIR [SUBSTRING]: list DIR on the phone (iOS, USB up), depth <= 12: "mtime size path" of the entries
# whose path contains SUBSTRING. davinci's rfindt: /tmp/rfindt_args -> /tmp/rfindt.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
RFINDT=${RFINDT:-/home/marnov/xmiphones/davinci-ios/gpu/userland/metal/rfindt}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s\n%s' "$1" "${2:-}" > "$tmp"
python3 -I tools/push_file.py "$tmp" /tmp/rfindt_args 0644 >/dev/null
python3 -I tools/push_file.py "$RFINDT" /tmp/rfindt 0755 >/dev/null
for _ in $(seq 1 60); do
	sleep 1
	if python3 -I tools/read_file.py /tmp/rfindt.txt > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
		cat "$tmp"
		exit 0
	fi
done
echo "rfind.sh: no listing of $1" >&2
exit 1
