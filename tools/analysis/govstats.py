#!/usr/bin/env python3
"""govstats.py TAG "NAME:..." ...: the clocks, battery and temperatures per setting and section of a bench81-ab run.

Reads out/logs/gov/TAG-NAME-cN-SECTION.{a,b} (tools/bench81.sh's snapshots of the xnu 0151 sysctls
kern.sweet_dvfs_stats, kern.sweet_power, kern.sweet_temps) and prints, averaged over the cycles: the average MHz
asked of L3, silver, gold, prime and the GPU; the battery's average current and power (drawn positive; with the
USB cable in, the charger's share is not seen, so compare settings, not absolute numbers); the hottest big-core and
GPU sensor reached.
"""
import glob, os, re, sys
from collections import defaultdict

SECTIONS = ('home', 'settings', 'switcher', 'idle', 'hcr')


def parse(path):
    out = {}
    try:
        text = open(path, errors='replace').read()
    except OSError:
        return None
    for name, body in re.findall(r'kern\.sweet_(\w+): (.*)', text):
        toks = body.split()
        vals = {}
        if name == 'temps':
            # silver S big B gpu G ddr D peak s b g d
            try:
                vals = dict(silver=int(toks[1]), big=int(toks[3]), gpu=int(toks[5]), ddr=int(toks[7]),
                            peak_big=int(toks[10]), peak_gpu=int(toks[11]))
            except (IndexError, ValueError):
                continue
        else:
            for k, v in zip(toks[::2], toks[1::2]):
                try:
                    vals[k] = int(v.split('/')[0])
                except ValueError:
                    pass
        out[name] = vals
    return out if 'dvfs_stats' in out else None


def section(tag, name, sec):
    rows = []
    for a in sorted(glob.glob(f'out/logs/gov/{tag}-{name}-c*-{sec}.a')):
        b = a[:-1] + 'b'
        pa, pb = parse(a), parse(b)
        if not pa or not pb:
            continue
        sa, sb = pa['dvfs_stats'], pb['dvfs_stats']
        ms = sb['ms'] - sa['ms']
        if ms <= 0:
            continue
        r = dict(s=ms / 1000)
        for k in ('l3', 'silver', 'gold', 'prime', 'gpu'):
            r[k] = (sb[k] - sa[k]) / ms
        wa, wb = pa.get('power'), pb.get('power')
        if wa and wb and wb.get('ms', 0) > wa.get('ms', 0):
            pms = wb['ms'] - wa['ms']
            r['ma'] = (wb['mAms'] - wa['mAms']) / pms
            r['mw'] = (wb['mWms'] - wa['mWms']) / pms
        t = pb.get('temps')
        if t:
            r['tbig'] = t['peak_big'] / 10
            r['tgpu'] = t['peak_gpu'] / 10
        rows.append(r)
    if not rows:
        return None
    avg = {}
    for k in rows[0]:
        vs = [r[k] for r in rows if k in r]
        avg[k] = (max(vs) if k.startswith('t') else sum(vs) / len(vs)) if vs else None
    avg['n'] = len(rows)
    return avg


def main():
    tag = sys.argv[1]
    names = [a.split(':')[0] for a in sys.argv[2:]]
    print(f'\n{"setting":10s} {"section":8s} {"n":>2s} {"secs":>5s} | {"L3":>5s} {"silver":>6s} {"gold":>5s} {"prime":>5s} '
          f'{"GPU":>4s} MHz avg | {"mA":>5s} {"mW":>5s} battery | {"big":>5s} {"GPU":>5s} °C peak')
    for sec in SECTIONS:
        for n in names:
            r = section(tag, n, sec)
            if not r:
                continue
            f = lambda k, w, d=0: (f'{r[k]:{w}.{d}f}' if r.get(k) is not None else ' ' * (w - 1) + '-')
            print(f'{n:10s} {sec:8s} {r["n"]:2d} {f("s", 5, 1)} | {f("l3", 5)} {f("silver", 6)} {f("gold", 5)} {f("prime", 5)} '
                  f'{f("gpu", 4)}         | {f("ma", 5)} {f("mw", 5)}         | {f("tbig", 5, 1)} {f("tgpu", 5, 1)}')


if __name__ == '__main__':
    main()
