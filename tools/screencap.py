#!/usr/bin/env python3
# Take a screenshot of the phone: run screencap on the device, pull /tmp/screen.raw, write a PNG.
# usage: screencap.py [out.png]   (default: /tmp/screen.png)
# Mi 9T Pro copy of davinci-ios/gpu/userland/metal/screencap.py: this repo's push/read (192.168.9.2); the
# device binary stays in davinci's folder (SCREENCAP= overrides), not in git.
import os, struct, subprocess, sys, time, zlib
HERE = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/screen.png"
surf = sys.argv[2] if len(sys.argv) > 2 else None      # an IOSurface id instead of the panel
remote = "/tmp/surf_%s.raw" % surf if surf else "/tmp/screen.raw"
if surf:
    open("/tmp/claude_ids", "w").write(surf)
    subprocess.run([sys.executable, os.path.join(HERE, "push_file.py"), "/tmp/claude_ids", "/tmp/screencap_ids", "0644"],
                   check=True, stdout=subprocess.DEVNULL)
subprocess.run([sys.executable, os.path.join(HERE, "push_file.py"), os.environ.get("SCREENCAP", os.path.join(HERE, "..", "out", "userland", "screencap")), "/tmp/screencap", "0755"],
               check=True, stdout=subprocess.DEVNULL)
data = b""
for _ in range(30):                     # it runs on its own once pushed; wait for the renamed file
    time.sleep(1)
    r = subprocess.run([sys.executable, os.path.join(HERE, "read_file.py"), remote], capture_output=True)
    data = r.stdout
    if len(data) > 16 and data[:4] == b"SCAP":
        w, h, bpr = struct.unpack_from("<III", data, 4)
        if len(data) >= 16 + h * bpr:
            break
else:
    sys.exit("no screenshot came back (got %d bytes)" % len(data))
rows = []
for y in range(h):
    row = data[16 + y * bpr: 16 + y * bpr + w * 4]
    rgb = bytearray(w * 3)
    rgb[0::3] = row[2::4]               # BGRA -> RGB
    rgb[1::3] = row[1::4]
    rgb[2::3] = row[0::4]
    rows.append(b"\x00" + bytes(rgb))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + \
      chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")
open(out, "wb").write(png)
print("%s %dx%d" % (out, w, h))
