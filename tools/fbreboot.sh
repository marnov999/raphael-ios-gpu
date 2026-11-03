#!/bin/bash
# fbreboot.sh [IMAGE]: from running iOS (USB gadget up, sweet_push on 192.168.9.2:5566) back into fastboot
# without touching the phone, and with IMAGE also `fastboot boot` it: the hands-free dev loop (davinci's).
# The kernel sets PON SOFT_RB_SPARE = bootloader and resets (xnu 0114 sweet_reboot.c, DRM
# MSM_INFO_IOS_REBOOT, called by davinci's fbreboot binary with /tmp/reboot_mode "1").
set -euo pipefail
cd "$(dirname "$0")/.."
FBREBOOT=${FBREBOOT:-/home/marnov/xmiphones/davinci-ios/gpu/userland/metal/fbreboot}
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf 1 > "$tmp"
python3 -I tools/push_file.py "$tmp" /tmp/reboot_mode 0644 >/dev/null
python3 -I tools/push_file.py "$FBREBOOT" /tmp/fbreboot 0755 >/dev/null
tools/fb.sh wait
[ -z "${1:-}" ] || tools/fb.sh boot "$1"
