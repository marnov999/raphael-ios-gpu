#!/bin/bash
# resign-app.sh APP [EXE]: re-sign an installed app's main executable ad hoc WITH ITS OWN ENTITLEMENTS
# (/Applications/APP.app/EXE on the phone; EXE defaults to APP). An IPA's executable keeps its App Store
# signature, which this port's kernel does not vouch for, so securityd / containermanager see NO
# entitlements: Minecraft's keychain write failed (-34018), Monument Valley's app-group storage read back
# wrong. The original is kept in backup/apps/EXE.phone-DATE (once); the re-signed file is pushed 0644 and
# given 0755 with gbx (sweet_push spawns files that arrive executable).
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:?app name, e.g. MonumentValley}; EXE=${2:-$1}
REMOTE="/Applications/$APP.app/$EXE"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
python3 -I tools/read_file.py "$REMOTE" > "$W/orig"
[ -s "$W/orig" ] || { echo "resign-app: could not read $REMOTE" >&2; exit 1; }
mkdir -p backup/apps
[ -e "backup/apps/$EXE.phone-$(date +%Y%m%d)" ] || cp "$W/orig" "backup/apps/$EXE.phone-$(date +%Y%m%d)"
ldid -e "$W/orig" > "$W/ents" 2>/dev/null || true
if ! grep -q '<dict>' "$W/ents"; then
	echo "resign-app: $EXE has no entitlements; nothing to carry over" >&2
	exit 0
fi
cp "$W/orig" "$W/new"
ldid -Hsha256 -Cadhoc -S"$W/ents" "$W/new"
python3 -I tools/push_file.py "$W/new" "$REMOTE" 0644 | tail -1
python3 -I - "$REMOTE" <<'EOF'
import sys
sys.path.insert(0, "/home/marnov/xmiphones/geekbench/tools")
import host
host.DEV = ("192.168.9.2", 5566)
print(host.gbx("chmod", "755", sys.argv[1]).splitlines()[1])
EOF
echo "resign-app: $EXE re-signed with $(grep -c '<key>' "$W/ents") entitlement keys"
