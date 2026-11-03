#!/bin/bash
# panel-hz.sh HZ: the panel's refresh rate, live (iOS up, xnu 0128 kern.sweet_mdss, /tmp/mdss pushed).
# The EA8076 runs its frames off the DSI bit clock: 60.214 Hz at the boot loader's 1103 MHz, 63.19 Hz at
# 1157.7 (measured 2026-11-03), so HZ needs 1103 MHz * HZ / 60.214. The DSI0 PLL is restarted on that rate
# between two panel frames, autorefresh paused (the panel shows its own RAM meanwhile): its decimal and
# fractional dividers (VCO = (dec + frac / 2^18) * 2 * 19.2 MHz; bit clock = VCO, dividers 1), then the
# PLL off and on with the PHY's global clock gated (vendor mdss-dsi-pll-7nm.c dsi_pll_enable/disable).
# Then measures the TEs. A reboot puts the boot loader's 60 Hz back.
set -euo pipefail
cd "$(dirname "$0")/.."
hz=${1:?usage: panel-hz.sh HZ}
read -r mhz dec frac < <(python3 -c "
hz=float('$hz'); v=1103.0e6*hz/60.214
if not 30 <= hz <= 91: raise SystemExit('panel-hz.sh: %s Hz is outside 30..91' % hz)
x=v/38.4e6; d=int(x); f=round((x-d)*2**18)
print('%.1f %x %x' % (v/1e6, d, f))")
f=$((16#$frac))
printf 'panel-hz: %s Hz: bit clock %s MHz, dec %s frac %s\n' "$hz" "$mhz" "$dec" "$frac"
tools/run.sh /tmp/mdss w "6bab4,0,sleep,20,949e0,$dec,949e4,$(printf %x $((f & 0xff))),949e8,$(printf %x $((f >> 8 & 0xff))),949ec,$(printf %x $((f >> 16 & 3))),94414,11,9443c,0,9443c,1,sleep,2,94414,31,6bab4,80000001" | grep -v "^runlog"
tools/run.sh /tmp/mdss r 94ab0 | sed 's/^/pll status (bit 0 locked): /' | grep -v "^pll status (bit 0 locked): runlog"
tools/run.sh /tmp/mdss te 3 | grep -v "^runlog"
