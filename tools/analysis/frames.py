#!/usr/bin/env python3
"""
frames.py (2026-11-07): one frame-pacing report for MIUI and iOS benches, so the two compare.

  frames.py miui TRACE...        atrace text from tools/bench-miui.sh (out/logs/miui/TAG-N.txt)
  frames.py refreshes FILE...    "SECTION T_MS" lines: the times of the panel refreshes that showed a new frame
                                 (tools/analysis/ios-refreshes.py makes them from an iOS bench log)

A "frame" is a refresh of the panel that showed something new: on MIUI the display HAL's present
(HWCSession::PresentDisplay; two within 6 ms are one refresh), on iOS a flip of the framebuffer.
Inside a section (its begin mark to 1.5 s past its end) a gap over IDLE_MS between frames is a still
screen, not a drop: the same rule for both systems. A gap of k+1 panel periods
is a frame shown k extra refreshes: k "repeats". Repeat % = repeats / all refreshes in the animations.
Spread: the drop events by length, and how many come close to another (within CLUSTER refreshes).
Clocks (MIUI): time-weighted residency of each CPU cluster, the GPU, its bus vote and the L3 vote inside
the sections, and every change with its time into TRACE-clocks.csv.
"""
import collections
import re
import statistics
import sys

IDLE_MS = 70.0
MERGE_MS = 6.0
CLUSTER = 4

LINE = re.compile(r'\s(\d+\.\d+): ([a-z_0-9]+): (.*)')


def pct(xs, p):
    xs = sorted(xs)
    if not xs:
        return float('nan')
    i = min(len(xs) - 1, max(0, int(round(p / 100.0 * (len(xs) - 1)))))
    return xs[i]


# layers whose updates are not the animation the bench looks at (MIUI's live wallpaper redraws ~47 times a
# second all the time; the bars and corners now and then)
NOT_CONTENT = re.compile(r'SuperWallpaper|Wallpaper|NavigationBar|StatusBar|RoundCorner|ScreenDecor|Toast')


APPS = ('com.miui.home', 'ndroid.settings')    # the animating programs (their main threads' names)
TASK = re.compile(r'^\s*(.+?)-(\d+)\s+\(\s*(\d+)\)')


def parse_miui(path):
    pres, marks, ev = [], [], []
    applied, last = [], {}
    start = {}
    apps, dof, draw = set(), collections.defaultdict(list), collections.defaultdict(list)
    for l in open(path, errors='replace'):
        if 'Choreographer#doFrame' in l or '|DrawFrame' in l:
            tm, mm = TASK.match(l), LINE.search(l)
            if tm and mm:
                tg = int(tm.group(3))
                if tm.group(1) in APPS and tm.group(2) == tm.group(3):
                    apps.add(tg)
                (dof if 'doFrame' in l else draw)[tg].append(float(mm.group(1)))
        m = LINE.search(l)
        if not m:
            continue
        t, kind, rest = float(m.group(1)), m.group(2), m.group(3)
        if kind == 'tracing_mark_write':
            if rest.endswith('|HWCSession::PresentDisplay::') and rest.startswith('B|'):
                pres.append(t)
            elif rest.startswith('atouch: clocks start'):
                for kv in rest.split()[3:]:
                    k, _, v = kv.partition('=')
                    start[k] = v
                marks.append((t, 'clocks'))
            elif rest.startswith('atouch: '):
                marks.append((t, rest[8:].strip()))
            elif rest.startswith('C|') and '#' in rest:
                # a layer's queued buffers ("NAME") or transactions ("TX - NAME"): a drop = SF took one
                p = rest.split('|')
                if len(p) >= 4 and not NOT_CONTENT.search(p[2]):
                    try:
                        v = int(p[3])
                    except ValueError:
                        v = None
                    if v is not None:
                        if v < last.get(p[2], v + 1) and p[2] in last:
                            applied.append(t)
                        last[p[2]] = v
        elif kind == 'cpu_frequency':
            mm = re.match(r'state=(\d+) cpu_id=(\d+)', rest)
            if mm and int(mm.group(2)) in (0, 4, 7):
                ev.append((t, 'cpu%s' % mm.group(2), int(mm.group(1)) // 1000))
        elif kind == 'gpu_frequency':
            mm = re.match(r'state=(\d+)', rest)
            if mm:
                ev.append((t, 'gpu', int(mm.group(1)) // 1000))
        elif kind == 'kgsl_buslevel':
            mm = re.search(r'bus=(\d+)', rest)
            if mm:
                ev.append((t, 'gpubus', int(mm.group(1))))
        elif kind == 'memlat_dev_update':
            mm = re.search(r'dev: soc:qcom,(cpu\d-cpu-l3-lat), .*vote=(\d+)', rest)
            if mm:
                ev.append((t, 'l3_' + mm.group(1)[:4], int(mm.group(2)) // 1000000))
        elif kind == 'bw_hwmon_update':
            mm = re.search(r'dev: soc:qcom,(cpu-llcc-ddr-bw), mbps = (\d+)', rest)
            if mm:
                ev.append((t, 'ddr_mbps', int(mm.group(2))))
    init = {}
    for k in ('cpu0', 'cpu4', 'cpu7'):
        if k in start:
            init[k] = int(start[k]) // 1000
    if 'gpu' in start:
        init['gpu'] = int(start['gpu']) // 1000000
    refreshes = []
    for t in sorted(pres):
        if refreshes and (t - refreshes[-1]) * 1000 < MERGE_MS:
            continue
        refreshes.append(t)
    # the refreshes that showed new content: the first present after SF took a buffer/transaction of it
    import bisect
    content = sorted(set(refreshes[i] for i in (bisect.bisect_left(refreshes, a) for a in applied) if i < len(refreshes)))
    # quiet frames: an animating program's frame tick (doFrame) that drew nothing (no DrawFrame before its next
    # tick): nothing on screen changed, so a refresh without new content there is no visible miss (iOS: still tail)
    quiet = []
    for tg in apps:
        d, dr = sorted(dof[tg]), sorted(draw[tg])
        for a, b in zip(d, d[1:] + [d[-1] + 0.0167]):
            i = bisect.bisect_left(dr, a)
            if not (i < len(dr) and dr[i] < b):
                quiet.append(a)
    return refreshes, content, marks, ev, init, sorted(quiet)


def visible(content, quiet, sec, P=1000 / 60.0, tail=1.5):
    """(repeats, still, visible) in a section: a drop's repeats are still as far as the programs had quiet
    frame ticks two periods before (when the frame for those refreshes would have been drawn)"""
    import bisect
    name, s, e, gest = sec
    cs = [c for c in content if s <= c < e + tail]
    reps = still = 0
    for a, b in zip(cs, cs[1:]):
        d = (b - a) * 1000
        if d > IDLE_MS:
            continue
        k = max(0, int(round(d / P)) - 1)
        if k:
            lo, hi = a - 2 * P / 1000, b - 2 * P / 1000
            q = bisect.bisect_right(quiet, hi) - bisect.bisect_right(quiet, lo)
            reps += k
            still += min(k, q)
    return reps, still, reps - still


def sections(marks):
    """(name, start, end, [gesture times]) from the marks "home begin" ... "home end" """
    out, cur = [], None
    for t, w in marks:
        if w.endswith(' begin'):
            cur = [w[:-6], t, None, []]
        elif w.endswith(' end') and cur:
            cur[2] = t
            out.append(tuple(cur))
            cur = None
        elif cur and (w.startswith('swipe') or w.startswith('tap')):
            cur[3].append(t)
    return out


MAIN_MS = 600.0


def gaps_of(times, main_only=False):
    """the gaps between consecutive frames (seconds in, ms out), leaving out the still screen (over IDLE_MS);
    main_only: only the first MAIN_MS of each burst (an animation's main part, not its settling tail)"""
    out, burst = [], None
    for a, b in zip(times, times[1:]):
        d = (b - a) * 1000
        if d > IDLE_MS:
            burst = None
            continue
        if burst is None:
            burst = a
        if not main_only or (a - burst) * 1000 < MAIN_MS:
            out.append(d)
    return out


def section_gaps(refreshes, sec, tail=1.5, main_only=False):
    name, s, e, gest = sec
    return gaps_of([r for r in refreshes if s <= r < e + tail], main_only)


def report(name, gaps, period=None):
    if not gaps:
        print('%-10s no frames' % name)
        return None
    P = period or statistics.median(gaps)
    ks = [max(0, int(round(d / P)) - 1) for d in gaps]
    refreshes = sum(k + 1 for k in ks)
    reps = sum(ks)
    drops = [i for i, k in enumerate(ks) if k > 0]
    pos, acc = [], 0
    for k in ks:
        acc += k + 1
        pos.append(acc)
    near = sum(1 for a in drops if any(b != a and abs(pos[a] - pos[b]) <= CLUSTER for b in drops))
    hist = collections.Counter(min(k, 3) for k in ks if k > 0)
    total_ms = sum(gaps)
    r = dict(name=name, frames=len(gaps), period=P, avg=1000.0 * len(gaps) / total_ms,
             med=1000.0 / statistics.median(gaps), p99ms=pct(gaps, 99), p999ms=pct(gaps, 99.9),
             low1=1000.0 / pct(gaps, 99), worst=max(gaps), reps=reps, refreshes=refreshes,
             reppct=100.0 * reps / refreshes, events=len(drops), h1=hist.get(1, 0), h2=hist.get(2, 0),
             h3=hist.get(3, 0), near=near, isolated=len(drops) - near)
    return r


def print_table(rows):
    cols = [('section', 'name', '%s'), ('frames', 'frames', '%d'), ('panel ms', 'period', '%.2f'),
            ('avg fps', 'avg', '%.1f'), ('median fps', 'med', '%.1f'), ('p99 ms', 'p99ms', '%.1f'),
            ('1% low fps', 'low1', '%.1f'), ('worst ms', 'worst', '%.1f'), ('repeat %', 'reppct', '%.2f'),
            ('drops', 'events', '%d'), ('1x', 'h1', '%d'), ('2x', 'h2', '%d'), ('3x+', 'h3', '%d'),
            ('isolated', 'isolated', '%d'), ('clustered', 'near', '%d')]
    print(' | '.join(c[0] for c in cols))
    for r in rows:
        if r:
            print(' | '.join(c[2] % r[c[1]] for c in cols))


def residency(ev, init, wins):
    """per domain: {value: seconds} inside the windows"""
    by = collections.defaultdict(list)
    for t, d, v in sorted(ev):
        by[d].append((t, v))
    out = {}
    for d in sorted(set(list(by) + list(init))):
        changes = by.get(d, [])
        res = collections.Counter()
        for s, e in wins:
            v = init.get(d)
            for t, nv in changes:
                if t <= s:
                    v = nv
            t0 = s
            for t, nv in changes:
                if s < t < e:
                    if v is not None:
                        res[v] += t - t0
                    v, t0 = nv, t
            if v is not None:
                res[v] += e - t0
        if res:
            out[d] = res
    return out


def main():
    mode = sys.argv[1]
    if mode == 'miui':
        allgaps = collections.defaultdict(list)
        vis = {}
        res_tot = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
        for path in sys.argv[2:]:
            refreshes, content, marks, ev, init, quiet = parse_miui(path)
            secs = sections(marks)
            for sec in secs:
                vis[sec[0]] = [x + y for x, y in zip(vis.get(sec[0], [0, 0, 0]), visible(content, quiet, sec))]
                allgaps[sec[0] + ' (all presents)'] += section_gaps(refreshes, sec)
                allgaps[sec[0]] += section_gaps(content, sec)
                allgaps[sec[0] + ' (first 0.6 s)'] += section_gaps(content, sec, main_only=True)
                for d, res in residency(ev, init, [(sec[1], sec[2] + 1.5)]).items():
                    res_tot[sec[0]][d].update(res)
            t0 = marks[0][0] if marks else 0
            with open(path.rsplit('.', 1)[0] + '-clocks.csv', 'w') as f:
                f.write('t_ms,domain,value\n')
                for d, v in sorted(init.items()):
                    f.write('0.000,%s,%d\n' % (d, v))
                for t, w in marks:
                    f.write('%.3f,mark,%s\n' % ((t - t0) * 1000, w.replace(',', ' ')))
                for t, d, v in sorted(ev):
                    if t >= t0:
                        f.write('%.3f,%s,%d\n' % ((t - t0) * 1000, d, v))
            with open(path.rsplit('.', 1)[0] + '-frames.csv', 'w') as f:
                f.write('t_ms,new_content\n')
                cs = set(content)
                for r in refreshes:
                    if r >= t0:
                        f.write('%.3f,%d\n' % ((r - t0) * 1000, r in cs))
        rows = [report(n, g, 1000 / 60.0) for n, g in sorted(allgaps.items())]
        print_table(rows)
        for n, (reps, still, v) in vis.items():
            r = [x for x in rows if x and x['name'] == n][0]
            print('%s: repeats %d = still (the program drew nothing new) %d + visible %d: visible %.2f%% of %d refreshes'
                  % (n, reps, still, v, 100.0 * v / r['refreshes'], r['refreshes']))
        units = {'cpu0': 'MHz', 'cpu4': 'MHz', 'cpu7': 'MHz', 'gpu': 'MHz', 'gpubus': 'level',
                 'l3_cpu0': 'MHz', 'l3_cpu4': 'MHz', 'l3_cpu7': 'MHz', 'ddr_mbps': 'MB/s'}
        for sec, doms in res_tot.items():
            print('\nclocks in %s (time-weighted):' % sec)
            for d, res in sorted(doms.items()):
                tot = sum(res.values())
                mean = sum(v * s for v, s in res.items()) / tot
                top = ', '.join('%d %.0f%%' % (v, 100 * s / tot) for v, s in sorted(res.items(), key=lambda x: -x[1])[:5])
                print('  %-9s mean %7.0f %-5s min %5d max %5d | most: %s' % (d, mean, units.get(d, ''), min(res), max(res), top))
    elif mode == 'refreshes':
        allgaps = collections.defaultdict(list)
        for path in sys.argv[2:]:
            times = collections.defaultdict(list)
            for l in open(path):
                p = l.split()
                if len(p) == 2:
                    times[p[0]].append(float(p[1]) / 1e6)
            for n, ts in times.items():
                allgaps[n] += gaps_of(sorted(ts))
                allgaps[n + ' (first 0.6 s)'] += gaps_of(sorted(ts), True)
        print_table([report(n, g) for n, g in sorted(allgaps.items())])


if __name__ == '__main__':
    main()
