#!/usr/bin/env python3
"""hfs-journal.py IMAGE: is the HFS+ volume's journal empty (safe for Linux to mount with "force")?
Reads the volume header (offset 1024: attributes, journalInfoBlock, blockSize), the journal info block and the
journal header (magic 'JNLx', start, end; empty when start == end). Prints the state; exit 0 = empty or no
journal, 1 = transactions not replayed (XNU would replay them over anything written now), 2 = not HFS+."""
import struct
import sys

f = open(sys.argv[1], 'rb')
f.seek(1024)
vh = f.read(512)
sig, version, attributes = struct.unpack_from('>2sHI', vh, 0)
if sig not in (b'H+', b'HX'):
    sys.exit(print(f'not HFS+ ({sig!r})') or 2)
journal_info_block, = struct.unpack_from('>I', vh, 12)
block_size, = struct.unpack_from('>I', vh, 40)
unmounted = bool(attributes & (1 << 8))
journaled = bool(attributes & (1 << 13))
print(f'{sig.decode()} v{version} block {block_size} attributes {attributes:#x}: cleanly unmounted {unmounted}, '
      f'journaled {journaled}')
if not journaled:
    sys.exit(0)
f.seek(journal_info_block * block_size)
flags, = struct.unpack_from(">I", f.read(4 + 32), 0)
f.seek(journal_info_block * block_size + 4 + 32)
offset, size = struct.unpack('>QQ', f.read(16))
f.seek(offset)
jh = f.read(32)
magic, endian, start, end, jsize = struct.unpack_from('>IIQQQ', jh, 0)
if magic == 0x4a4e4c78:
    pass
elif struct.unpack_from('<I', jh, 0)[0] == 0x4a4e4c78:
    magic, endian, start, end, jsize = struct.unpack_from('<IIQQQ', jh, 0)
else:
    sys.exit(print(f'journal header magic {magic:#x}: not a journal') or 1)
print(f'journal at {offset:#x} size {size:#x} (info flags {flags:#x}): start {start:#x} end {end:#x} -> '
      f'{"EMPTY" if start == end else "NOT EMPTY (transactions to replay)"}')
sys.exit(0 if start == end else 1)
