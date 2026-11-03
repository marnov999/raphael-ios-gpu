#!/usr/bin/env python3
"""hfs-journal-replay.py IMAGE [--apply]: replay an HFS+ volume's journal into the volume itself, as XNU does
when it mounts it (bsd/vfs/vfs_journal.c replay_journal), so that Linux -- which mounts a journaled HFS+ only
with "force" and never replays -- can then change it safely. Without --apply: only lists the transactions.

Layout (TN1150 "Journal"; vfs_journal.h): the volume header's journalInfoBlock names the journal info block
{flags, device_signature[32], offset u64, size u64}; at offset the journal header {magic 'JNLx', endian
0x12345678, start, end, size u64; blhdr_size, checksum, jhdr_size u32}, in the byte order of the machine that
wrote it. The journal is a ring from jhdr_size to size; start..end holds block lists one after another:
{max_blocks u16, num_blocks u16, bytes_used u32, checksum, flags-ish u32, binfo[num_blocks] {bnum u64, bsize
u32, next u32}} padded to blhdr_size, then the data of binfo[1..] in order. Block bnum is in units of jhdr_size
on the device; bnum == ~0 is a block cancelled later in the transaction (its data is skipped). Applied in
order; then start = end and the header is written back.
"""
import struct
import sys

img_path = sys.argv[1]
apply = '--apply' in sys.argv
f = open(img_path, 'r+b' if apply else 'rb')

f.seek(1024)
vh = f.read(512)
sig, version, attributes = struct.unpack_from('>2sHI', vh, 0)
assert sig in (b'H+', b'HX'), f'not HFS+: {sig!r}'
jib_block, = struct.unpack_from('>I', vh, 12)
block_size, = struct.unpack_from('>I', vh, 40)
total_blocks, = struct.unpack_from('>I', vh, 44)
vol_bytes = block_size * total_blocks
assert attributes & (1 << 13), 'volume is not journaled'

f.seek(jib_block * block_size)
jib = f.read(52)
jflags, = struct.unpack_from('>I', jib, 0)
joff, jsize = struct.unpack_from('>QQ', jib, 36)
assert jflags & 1 and not jflags & 2, f'journal info flags {jflags:#x}: not an in-volume journal'

f.seek(joff)
raw = f.read(44)
for E in ('<', '>'):
    magic, endian, start, end, size, blhdr_size, checksum, jhdr_size = struct.unpack_from(E + 'IIQQQIiI', raw, 0)
    if magic == 0x4a4e4c78 and endian == 0x12345678:
        break
else:
    sys.exit('no journal header')
print(f'journal at {joff:#x} ({"little" if E == "<" else "big"}-endian): start {start:#x} end {end:#x} size {size:#x} '
      f'blhdr_size {blhdr_size:#x} jhdr_size {jhdr_size:#x}; volume {vol_bytes:#x} bytes')
assert size == jsize and jhdr_size in (512, 4096) and blhdr_size % jhdr_size == 0


def jhdr_checksum(hdr44):
    # vfs_journal.c calc_checksum over JOURNAL_HEADER_CKSUM_SIZE (= offsetof(sequence_num) = 44) bytes,
    # the checksum field zeroed
    b = bytearray(hdr44)
    b[36:40] = b'\0\0\0\0'
    ck = 0
    for c in b:
        ck = ((ck << 8) ^ (ck + c)) & 0xffffffff
    return struct.unpack('i', struct.pack('I', ~ck & 0xffffffff))[0]


assert jhdr_checksum(raw) == checksum, f'journal header checksum {checksum:#x} != computed {jhdr_checksum(raw):#x}'


def jread(pos, n):
    """n bytes of the journal ring from position pos (wrapping past size to jhdr_size)."""
    out = b''
    while n:
        if pos >= size:
            pos = jhdr_size + (pos - size)
        k = min(n, size - pos)
        f.seek(joff + pos)
        out += f.read(k)
        pos += k
        n -= k
    return out, pos


writes = []                 # (device offset, data), in order
pos, lists = start, 0
while pos != end:
    hdr, _ = jread(pos, blhdr_size)
    max_blocks, num_blocks, bytes_used, cksum, bflags = struct.unpack_from(E + 'HHIiI', hdr, 0)
    assert 1 <= num_blocks <= max_blocks and blhdr_size <= bytes_used <= size, \
        f'block list at {pos:#x}: {num_blocks}/{max_blocks} blocks, {bytes_used:#x} bytes: not a block list'
    data_pos = pos + blhdr_size
    data_pos = data_pos if data_pos < size else jhdr_size + (data_pos - size)
    used = blhdr_size
    for i in range(1, num_blocks):
        bnum, bsize, nxt = struct.unpack_from(E + 'QII', hdr, 16 + 16 * i)
        data, data_pos = jread(data_pos, bsize)
        used += bsize
        if bnum == 0xffffffffffffffff:
            continue
        off = bnum * jhdr_size
        assert off + bsize <= vol_bytes, f'block {bnum:#x} ({bsize} bytes) past the volume'
        writes.append((off, data))
    assert used == bytes_used, f'block list at {pos:#x}: data {used:#x} != bytes_used {bytes_used:#x}'
    lists += 1
    pos = pos + bytes_used
    pos = pos if pos < size else jhdr_size + (pos - size)
print(f'{lists} block lists, {len(writes)} blocks ({sum(len(d) for _, d in writes)} bytes) to put back')
for off, data in writes[:12]:
    print(f'  {off:#014x} {len(data)} bytes')
if not apply:
    sys.exit(0)
for off, data in writes:
    f.seek(off)
    f.write(data)
new = bytearray(struct.pack(E + 'IIQQQIiI', magic, endian, end, end, size, blhdr_size, 0, jhdr_size))
struct.pack_into(E + 'i', new, 36, jhdr_checksum(new))
f.seek(joff)
f.write(new)
# The volume is consistent now, so mark it cleanly unmounted (kHFSVolumeUnmountedBit, 1 << 8) in the volume
# header and its copy 1024 bytes before the end, as fsck_hfs does: Linux's hfsplus mounts a volume without it
# read-only even with "force".
for vh_off in (1024, vol_bytes - 1024):
    f.seek(vh_off)
    attrs, = struct.unpack_from('>I', f.read(8), 4)
    f.seek(vh_off + 4)
    f.write(struct.pack('>I', attrs | 1 << 8))
f.flush()
print(f'replayed; journal start = end = {end:#x}; marked cleanly unmounted')
