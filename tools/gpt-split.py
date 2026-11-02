#!/usr/bin/env python3
"""gpt-split.py GPT_DIR OUT_DIR [IOS_GIB]

raphael's dual boot: split LUN 0's 'userdata' into 'iosdata' (the first IOS_GIB GiB, default 25, same
start sector) and 'userdata' (the rest, for MIUI; keeps the type, attributes and unique GUID), like
davinci-ios/dualboot/gpt_split.py did for the Mi 9T. Input, read off the phone (4 KiB sectors, T = LUN 0
size in sectors):
  GPT_DIR/lun0-head.bin  LBA 0-5      (protective MBR, header, 32-entry table, zero padding)
  GPT_DIR/lun0-tail.bin  LBA T-8..T-1 (backup table at T-5, backup header at T-1)
The 32-entry table has a free slot after userdata (#31), so it does not grow: #31 becomes iosdata
(new unique GUID), #32 userdata. Writes OUT_DIR/head-new.bin (LBA 0-2) and OUT_DIR/tail-new.bin
(LBA T-5..T-1), re-parses both independently and prints the dd lines. Writes nothing to any device.
"""
import os, struct, sys, uuid, zlib

S = 4096
HDR = '<8sIIIIQQQQ16sQIII'
KEYS = ('sig', 'rev', 'hsize', 'hcrc', 'res', 'cur', 'alt', 'first', 'last', 'guid', 'ent', 'n', 'esz', 'ecrc')


def parse_hdr(sec):
    h = dict(zip(KEYS, struct.unpack_from(HDR, sec, 0)))
    assert h['sig'] == b'EFI PART', 'no GPT header'
    b = bytearray(sec[:h['hsize']])
    b[16:20] = b'\0\0\0\0'
    assert zlib.crc32(b) & 0xffffffff == h['hcrc'], 'header crc'
    return h


def mk_hdr(h, cur, alt, ent, ecrc):
    b = struct.pack(HDR, b'EFI PART', h['rev'], h['hsize'], 0, 0, cur, alt, h['first'], h['last'], h['guid'], ent,
                    h['n'], h['esz'], ecrc).ljust(h['hsize'], b'\0')
    b = b[:16] + struct.pack('<I', zlib.crc32(b) & 0xffffffff) + b[20:]
    return b.ljust(S, b'\0')


def name(e):
    return e[56:128].decode('utf-16-le').rstrip('\0')


def entry(t, u, f, l, a, nm):
    return t + u + struct.pack('<QQQ', f, l, a) + nm.encode('utf-16-le').ljust(72, b'\0')


def table(buf, h, base_lba):
    off = (h['ent'] - base_lba) * S
    ents = buf[off:off + h['n'] * h['esz']]
    assert len(ents) == h['n'] * h['esz'] and zlib.crc32(ents) & 0xffffffff == h['ecrc'], 'entries crc'
    return ents


def check(head, tail, total):
    """Independent re-parse: CRCs, both tables equal, headers point at each other, no overlaps."""
    hm, hb = parse_hdr(head[S:2 * S]), parse_hdr(tail[4 * S:5 * S])
    em, eb = table(head, hm, 0), table(tail, hb, total - 5)
    assert em == eb, 'main and backup tables differ'
    assert (hm['cur'], hm['alt'], hb['cur'], hb['alt']) == (1, total - 1, total - 1, 1), 'header LBAs'
    parts = []
    for i in range(hm['n']):
        r = em[i * 128:(i + 1) * 128]
        if r[:16] == b'\0' * 16:
            continue
        f, l, _ = struct.unpack_from('<QQQ', r, 32)
        assert hm['first'] <= f <= l <= hm['last'], 'outside the usable range: ' + name(r)
        parts.append((f, l, i + 1, name(r), str(uuid.UUID(bytes_le=r[16:32]))))
    parts.sort()
    for a, b in zip(parts, parts[1:]):
        assert a[1] < b[0], 'overlap %s %s' % (a[3], b[3])
    return parts


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    gib = int(sys.argv[3]) if len(sys.argv) > 3 else 25
    head = open(os.path.join(src, 'lun0-head.bin'), 'rb').read()
    tail = open(os.path.join(src, 'lun0-tail.bin'), 'rb').read()
    assert len(head) == 6 * S and len(tail) == 8 * S
    hm = parse_hdr(head[S:2 * S])
    total = hm['alt'] + 1
    hb = parse_hdr(tail[7 * S:8 * S])
    assert (hm['ent'], hm['n'], hm['esz'], hb['ent'], hm['first']) == (2, 32, 128, total - 5, 6), 'unexpected layout'
    em = table(head, hm, 0)
    assert em == table(tail[3 * S:], hb, total - 5), 'phone tables differ'
    rows = [em[i * 128:(i + 1) * 128] for i in range(32)]
    assert name(rows[30]) == 'userdata' and rows[31] == b'\0' * 128, 'userdata is not #31 with #32 free'
    assert all(name(r) != 'iosdata' for r in rows), 'already split'
    t, u = rows[30][:16], rows[30][16:32]
    f, l, a = struct.unpack_from('<QQQ', rows[30], 32)
    assert l == hm['last'], 'userdata does not end at the last usable LBA'
    ios_last = f + gib * (1 << 30) // S - 1
    assert ios_last < l
    new = rows[:30] + [entry(t, uuid.uuid4().bytes_le, f, ios_last, a, 'iosdata'), entry(t, u, ios_last + 1, l, a, 'userdata')]
    ents = b''.join(new)
    ecrc = zlib.crc32(ents) & 0xffffffff
    head_new = head[:S] + mk_hdr(hm, 1, total - 1, 2, ecrc) + ents
    tail_new = ents + b'\0' * (3 * S) + mk_hdr(hb, total - 1, 1, total - 5, ecrc)
    assert len(head_new) == 3 * S and len(tail_new) == 5 * S
    # only table sectors change: the padding around them stays zero as it was on the phone
    assert head[3 * S:6 * S] == b'\0' * 3 * S and tail[4 * S:7 * S] == b'\0' * 3 * S
    parts = check(head_new + head[3 * S:], tail_new, total)
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'head-new.bin'), 'wb').write(head_new)
    open(os.path.join(out, 'tail-new.bin'), 'wb').write(tail_new)
    for p in parts[-3:]:
        print('#%-2d %-9s sectors %d-%d  %.2f GiB  %s' % (p[2], p[3], p[0], p[1], (p[1] - p[0] + 1) * S / (1 << 30), p[4]))
    print('%d partitions, no overlaps, CRCs ok' % len(parts))
    # conv=notrunc: Android's toybox dd otherwise ftruncate()s the output, which fails on a block device
    # once seek > 0 ("ftruncate: Invalid argument", nothing written), and it has no conv=fsync: sync after
    print('dd if=head-new.bin of=/dev/block/sda bs=4096 seek=0 count=3 conv=notrunc')
    print('dd if=tail-new.bin of=/dev/block/sda bs=4096 seek=%d count=5 conv=notrunc && sync' % (total - 5))


if __name__ == '__main__':
    main()
