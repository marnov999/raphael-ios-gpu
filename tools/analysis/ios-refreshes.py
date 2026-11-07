#!/usr/bin/env python3
"""
ios-refreshes.py SECTION PROF... : the panel refreshes that showed a new frame in iOS bench profiles
(measure.sh's prof_TAG.txt: "TL v" = the vsync ticks, on the panel's TEs with sweetfb_telock=1; "TL s" = the
window server's swaps, field 4 the flip time, 0 if never flipped). A flipped frame is on screen from the
first tick after its flip. Prints "SECTION T_US" lines for tools/analysis/frames.py refreshes.
"""
import bisect
import re
import sys

sec = sys.argv[1]
for path in sys.argv[2:]:
    t = open(path, 'rb').read().decode('utf-8', 'replace')
    b = t.rfind('TL begin')
    e = t.find('TL end', b)
    seg = t[b:e]
    ticks = sorted(int(x) for x in re.findall(r'TL v (\d+)', seg))
    shown = set()
    for m in re.finditer(r'TL s (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)', seg):
        flip = int(m.group(4))
        if flip:
            i = bisect.bisect_right(ticks, flip)
            if i < len(ticks):
                shown.add(ticks[i])
    for s in sorted(shown):
        print(sec, s)
