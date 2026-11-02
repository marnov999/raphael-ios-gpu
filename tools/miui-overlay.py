#!/usr/bin/env python3
"""miui-overlay.py RAMDISK.cpio FSTAB OUT.cpio [--test]

MIUI on an unencrypted userdata, without touching vendor (dm-verity): adds to the Magisk ramdisk that
the boot image chain-loads (tools/unpack-miui-boot.py, tools/mkcombo.py)
  overlay.d/sbin/fstab.qcom      FSTAB (the phone's /vendor/etc/fstab.qcom) with the userdata entry's
                                 fileencryption= and inlinecrypt removed and formattable added
  overlay.d/raphael-data.rc      on late-fs: mount_all from that copy, ahead of vendor's mount_all
Magisk copies overlay.d/sbin into its tmpfs (${MAGISKTMP}, /debug_ramdisk on this phone) and merges
overlay.d/*.rc into init.rc. A userdata already encrypted with FBE must not be mounted from the
unencrypted fstab: use it only on a freshly formatted userdata.

--test: the fstab unchanged except for one marker comment, to check the mechanism on the current
(encrypted) MIUI: afterwards `grep raphael-ios-gpu /vendor/etc/fstab.qcom` must find it.
"""
import struct, sys

MARK = '# raphael-ios-gpu overlay (shim boot image, tools/miui-overlay.py)'
# How /data gets mounted from our fstab: not a bind mount over /vendor/etc/fstab.qcom. init's own mount
# is refused (avc denied { mounton } init -> vendor_configs_file), and done as Magisk (exec u:r:magisk:s0)
# both encrypted test boots, in early-fs and in on init, ended in recovery with
# --reason=enablefilecrypto_failed (2026-11-02). Instead: Magisk merges overlay.d/*.rc into init.rc, whose
# late-fs actions run before vendor's init.target.rc ones, so this mount_all mounts /data from our copy
# first and vendor's `mount_all /vendor/etc/fstab.qcom --late` finds it mounted and skips it.
RC = '''# raphael-ios-gpu: MIUI's userdata from our fstab (tools/miui-overlay.py)
on late-fs
    mount_all ${MAGISKTMP}/fstab.qcom --late
'''


def patch_fstab(text, test):
    out, hits = [MARK], 0
    for line in text.splitlines():
        f = line.split()
        if not test and len(f) >= 5 and not line.lstrip().startswith('#') and f[1] == '/data':
            opts = ','.join(o for o in f[3].split(',') if o != 'inlinecrypt')
            flags = [x for x in f[4].split(',') if not x.startswith('fileencryption=') and x not in
                     ('wrappedkey', 'forceencrypt', 'forcefdeorfbe', 'encryptable', 'fileencryption')]
            if 'formattable' not in flags:
                flags.append('formattable')
            line = '%-55s %-24s %-7s %-56s %s' % (f[0], f[1], f[2], opts, ','.join(flags))
            hits += 1
        out.append(line)
    if not test and hits != 1:
        raise SystemExit('expected exactly one /data entry, found %d' % hits)
    return '\n'.join(out) + '\n'


def entries(data):
    """newc cpio -> [(name, mode, data)] up to the trailer."""
    out, off = [], 0
    while True:
        assert data[off:off + 6] == b'070701', 'not a newc cpio at %#x' % off
        f = [int(data[off + 6 + 8 * i:off + 14 + 8 * i], 16) for i in range(13)]
        mode, size, nsize = f[1], f[6], f[11]
        name = data[off + 110:off + 110 + nsize - 1].decode()
        off = (off + 110 + nsize + 3) & ~3
        body = data[off:off + size]
        off = (off + size + 3) & ~3
        if name == 'TRAILER!!!':
            return out
        out.append((name, mode, body, f[2], f[3]))


def newc(items):
    out = b''
    for ino, (name, mode, body, uid, gid) in enumerate(items + [('TRAILER!!!', 0, b'', 0, 0)], 1):
        n = name.encode() + b'\0'
        hdr = '070701' + ''.join('%08x' % v for v in (ino if name != 'TRAILER!!!' else 0, mode, uid, gid,
                                                        2 if mode & 0o40000 else 1, 0, len(body), 0, 0, 0, 0,
                                                        len(n), 0))
        rec = hdr.encode() + n
        rec += b'\0' * (-len(rec) % 4) + body
        out += rec + b'\0' * (-len(rec) % 4)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 3:
        raise SystemExit(__doc__)
    test = '--test' in sys.argv
    items = entries(open(args[0], 'rb').read())
    names = [i[0] for i in items]
    assert 'overlay.d/sbin' in names and 'init' in names, 'not a Magisk ramdisk'
    items = [i for i in items if i[0] not in ('overlay.d/sbin/fstab.qcom', 'overlay.d/raphael-data.rc')]
    fstab = patch_fstab(open(args[1]).read(), test)
    items.append(('overlay.d/sbin/fstab.qcom', 0o100644, fstab.encode(), 0, 0))
    items.append(('overlay.d/raphael-data.rc', 0o100644, RC.encode(), 0, 0))
    open(args[2], 'wb').write(newc(items))
    for line in fstab.splitlines():
        if ' /data ' in ' %s ' % line and not line.startswith('#'):
            print(line)
    print('%s: %d entries (%s)' % (args[2], len(items), 'test marker only' if test else 'userdata unencrypted'))


if __name__ == '__main__':
    main()
