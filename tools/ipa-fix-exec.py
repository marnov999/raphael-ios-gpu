#!/usr/bin/env python3
"""ipa-fix-exec.py X.ipa [...]: chmod 755, on the phone, every Mach-O of the apps installed from these IPAs
(tools/ipa-install.py took executables from the unpacked files' mode bits, which the IPA's zip did not give:
2026-11-03 the apps' binaries stayed 0644 and xpcproxy's access(X_OK) failed EACCES -- "the app crashes")."""
import os
import sys
import zipfile

sys.path.insert(0, "/home/marnov/xmiphones/geekbench/tools")
import host  # noqa: E402

host.DEV = ("192.168.9.2", 5566)
MAGIC = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")
for ipa in sys.argv[1:]:
    z = zipfile.ZipFile(ipa)
    paths = []
    for i in z.infolist():
        if not i.filename.startswith("Payload/") or i.is_dir() or i.file_size < 4:
            continue
        with z.open(i) as f:
            if f.read(4) in MAGIC:
                paths.append("/Applications/" + i.filename[len("Payload/"):])
    for n in range(0, len(paths), 40):
        out = host.gbx("chmod", "755", *paths[n:n + 40], timeout=60)
        bad = [l for l in out.splitlines() if l.startswith("chmod") and not l.endswith(": ok")]
        for l in bad:
            print("  " + l)
    print("%s: %d Mach-O files chmod 755" % (os.path.basename(ipa), len(paths)))
