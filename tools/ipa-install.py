#!/usr/bin/env python3
"""ipa-install.py X.ipa [Y.ipa ...]: install apps on the Mi 9T Pro's iOS (USB gadget up) as davinci's were.

davinci's installer (geekbench/tools/host.py: unpack, refuse a FairPlay-encrypted binary, mkdir every
directory, push every file, then the on-device gbx registers the bundle through LaunchServices /
MobileInstallation) pointed at 192.168.9.2. One change: sweet_push spawns every file that arrives with an
exec bit, so executables are pushed 0644 and given 0755 with one `gbx chmod` afterwards -- the app's
binaries are not started half-installed.
"""
import os
import shutil
import sys
import time

sys.path.insert(0, "/home/marnov/xmiphones/geekbench/tools")
import host  # noqa: E402

host.DEV = ("192.168.9.2", 5566)


def cryptid(path):
    """LC_ENCRYPTION_INFO_64 cryptid of the arm64 slice (a fat binary's too; host.py reads only thin ones)."""
    import struct
    d = open(path, "rb").read()
    base = 0
    if d[:4] == b"\xca\xfe\xba\xbe":                   # fat: big-endian header, the arm64 slice
        n = struct.unpack(">I", d[4:8])[0]
        for i in range(n):
            ctype, _, off, size, _ = struct.unpack(">iiIII", d[8 + 20 * i:28 + 20 * i])
            if ctype == 0x0100000c:
                base = off
                break
        else:
            return None
    magic, _, _, _, ncmds = struct.unpack("<IiiII", d[base:base + 20])
    if magic != 0xfeedfacf:
        return None
    at = base + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", d[at:at + 8])
        if cmd == 0x2c:                                    # LC_ENCRYPTION_INFO_64
            return struct.unpack("<I", d[at + 16:at + 20])[0]
        at += size
    return 0


def install(ipa):
    work = os.path.join(host.ROOT, "work", os.path.basename(ipa) + ".d")
    mine = not os.path.exists(work)                 # (davinci's own unpacked copies are left alone)
    os.makedirs(work, exist_ok=True)
    appdir = host.unpack_ipa(ipa, work).rstrip("/")
    name = os.path.basename(appdir)
    dest = os.path.join("/Applications", name)
    import plistlib
    with open(os.path.join(appdir, "Info.plist"), "rb") as f:
        exe = plistlib.load(f).get("CFBundleExecutable")
    if not exe or not os.path.exists(os.path.join(appdir, exe)):
        print("[ipa] %s: no CFBundleExecutable %r, skipped" % (ipa, exe))
        return False
    cid = cryptid(os.path.join(appdir, exe))
    if cid:
        print("[ipa] %s: FairPlay-encrypted (cryptid=%d), skipped" % (ipa, cid))
        return False
    bid = host.bundle_id(appdir)
    dirs, files = [], []
    for root, _, fnames in os.walk(appdir):
        rel = os.path.relpath(root, appdir)
        tgt = dest if rel == "." else os.path.join(dest, rel)
        dirs.append(tgt)
        for fn in fnames:
            files.append((os.path.join(root, fn), os.path.join(tgt, fn)))
    total = sum(os.path.getsize(l) for l, _ in files)
    print("[ipa] %s -> %s (%s): %d dirs, %d files, %.0f MB" % (name, dest, bid, len(dirs), len(files), total / 1e6))
    for i in range(0, len(dirs), 200):
        host.gbx("mkdirp", *dirs[i:i + 200], timeout=60)
    t0 = time.time()
    execs = []
    for n, (local, remote) in enumerate(files, 1):
        if os.access(local, os.X_OK):
            execs.append(remote)
        ack = host.push(local, remote, 0o644)
        if ack != b"K":
            print("[ipa] ack %r for %s" % (ack, remote))
        if n % 200 == 0:
            print("[ipa] %d/%d" % (n, len(files)))
    dt = time.time() - t0
    print("[ipa] pushed in %.0f s (%.1f MB/s)" % (dt, total / 1e6 / max(dt, 0.001)))
    for i in range(0, len(execs), 200):
        host.gbx("chmod", "755", *execs[i:i + 200], timeout=60)
    out = host.gbx("install", dest, bid or "", timeout=120)
    print("\n".join(l for l in out.splitlines() if l and not l.startswith(("NONCE", "DONE"))))
    if mine:
        shutil.rmtree(work, ignore_errors=True)    # (the host's disk is short; the .ipa stays)
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if not host.up():
        sys.exit("phone not reachable at 192.168.9.2:5566")
    for ipa in sys.argv[1:]:
        install(ipa)
