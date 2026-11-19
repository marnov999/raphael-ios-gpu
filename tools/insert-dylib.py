#!/usr/bin/env python3
"""insert-dylib.py BINARY DYLIB_PATH: add an LC_LOAD_WEAK_DYLIB for DYLIB_PATH to a thin arm64 (or the
arm64 slice of a fat) Mach-O, in the padding between the load commands and the first section. The code
signature is NOT updated: re-sign afterwards (ldid -S). Refuses if the command is already there or does not
fit. Used for app shims that must load on every launch (userland/kvsshim)."""
import struct, sys

path, dylib = sys.argv[1], sys.argv[2]
data = bytearray(open(path, 'rb').read())
base = 0
if data[:4] == b'\xca\xfe\xba\xbe':
    n = struct.unpack('>I', data[4:8])[0]
    for i in range(n):
        ct, _, off, size, _ = struct.unpack('>iiIII', data[8 + 20 * i:28 + 20 * i])
        if ct == 0x0100000c:
            base = off
            break
    else:
        sys.exit('no arm64 slice')
magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', data[base:base + 32])
assert magic == 0xfeedfacf, hex(magic)
p, first_sect = base + 32, None
for _ in range(ncmds):
    cmd, sz = struct.unpack('<II', data[p:p + 8])
    if cmd in (0xc, 0x80000018):
        noff = struct.unpack('<I', data[p + 8:p + 12])[0]
        name = data[p + noff:p + sz].split(b'\0')[0].decode()
        if name == dylib:
            sys.exit('already loads ' + dylib)
    if cmd == 0x19:
        nsect = struct.unpack('<I', data[p + 64:p + 68])[0]
        for k in range(nsect):
            s = data[p + 72 + 80 * k:p + 72 + 80 * (k + 1)]
            off = struct.unpack('<I', s[48:52])[0]
            if off and (first_sect is None or off < first_sect):
                first_sect = off
    p += sz
name = dylib.encode() + b'\0'
cmdsize = (24 + len(name) + 7) & ~7
lc = struct.pack('<IIIIII', 0x80000018, cmdsize, 24, 2, 0x10000, 0x10000) + name
lc += b'\0' * (cmdsize - len(lc))
end = base + 32 + sizeofcmds
if first_sect is None or end + cmdsize > base + first_sect:
    sys.exit('no room for the load command (%s bytes free)' % ((base + first_sect - end) if first_sect else '?'))
if any(data[end:end + cmdsize]):
    sys.exit('the padding is not empty')
data[end:end + cmdsize] = lc
struct.pack_into('<II', data, base + 16, ncmds + 1, sizeofcmds + cmdsize)
open(path, 'wb').write(data)
print('added LC_LOAD_WEAK_DYLIB %s (%d bytes, %d free before)' % (dylib, cmdsize, base + first_sect - end))
