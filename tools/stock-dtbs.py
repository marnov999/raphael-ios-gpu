#!/usr/bin/env python3
"""Collect the SoC device trees from raphael's stock boot.img for our boot image.

  python3 tools/stock-dtbs.py BOOT.img OUT.dtb [--badram]

The stock image is boot header v1 with four DTBs appended to Image.gz (MIUI
V12.5.2.0.RFKMIXM: SM8150P v2, SM8150P v1, SM8150 v2, SM8150 v1; the CN firmware
lists them in another order). Our image is header v2, whose DTB section may hold
several concatenated DTBs: ABL picks the one matching the SoC's msm-id, applies the
dtbo overlays and hands the result to the shim. So all of them go in, in stock
order, instead of guessing the phone's SoC revision.

--badram adds /reserved-memory/badram@1016a0000 (no-map, 128 KiB) to each DTB:
this phone's weak DRAM cells (0x1016aa000-0x1016bdfff). Needed only where a Linux
kernel boots with these trees (MIUI); XNU never maps that range (tools/mkadt.py).
"""
import os, struct, subprocess, sys, tempfile

BADRAM = ('badram@1016a0000', [0x1, 0x016a0000, 0x0, 0x20000])


def find_dtbs(data):
    out, pos = [], 0
    while True:
        i = data.find(b'\xd0\x0d\xfe\xed', pos)
        if i < 0:
            return out
        size = struct.unpack('>I', data[i + 4:i + 8])[0]
        if 0x1000 < size < 0x400000 and i + size <= len(data):
            out.append(data[i:i + size])
            pos = i + size
        else:
            pos = i + 4


def add_badram(blob):
    """fdtput on a temporary copy: the node with reg + an empty no-map (fdtput with no value writes an
    empty property, byte-identical to the reservation validated in kbuild/boot-resv.img)."""
    name, reg = BADRAM
    with tempfile.NamedTemporaryFile(suffix='.dtb', delete=False) as f:
        f.write(blob)
        path = f.name
    try:
        subprocess.run(['fdtput', '-c', path, '/reserved-memory/' + name], check=True)
        subprocess.run(['fdtput', '-t', 'x', path, '/reserved-memory/' + name, 'reg'] + ['%x' % v for v in reg],
                       check=True)
        subprocess.run(['fdtput', path, '/reserved-memory/' + name, 'no-map'], check=True)
        return open(path, 'rb').read()
    finally:
        os.unlink(path)


def model(blob):
    with tempfile.NamedTemporaryFile(suffix='.dtb', delete=False) as f:
        f.write(blob)
        path = f.name
    try:
        r = subprocess.run(['fdtget', path, '/', 'model'], capture_output=True, text=True)
        return r.stdout.strip() or '?'
    finally:
        os.unlink(path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 2:
        raise SystemExit(__doc__)
    dtbs = find_dtbs(open(args[0], 'rb').read())
    if not dtbs:
        raise SystemExit('no DTB found: is this raphael\'s boot.img?')
    if '--badram' in sys.argv:
        dtbs = [add_badram(d) for d in dtbs]
    with open(args[1], 'wb') as f:
        for d in dtbs:
            print(f'{len(d):7d} bytes  {model(d)}')
            f.write(d)
    print(f'{args[1]}: {len(dtbs)} DTBs')


if __name__ == '__main__':
    main()
