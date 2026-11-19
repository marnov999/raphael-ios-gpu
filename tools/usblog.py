#!/usr/bin/env python3
"""usblog.py OUT.log [PORT]: write the Mi 9T Pro's live kernel console (xnu 0107: UDP from 192.168.9.2 to
port 5149 over USB ethernet, host connection enx02005e77ef01 = 192.168.9.1) to OUT.log as it arrives."""
import socket
import sys

import os
path = sys.argv[1]
CAP = 512 << 20     # bytes: past this the file becomes PATH.old and a new one starts (at most ~1 GB on disk;
                    # 2026-11-19 a window-server error loop ran 7 h unattended and wrote 1.6 GB)
out = open(path, 'ab', buffering=0)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('0.0.0.0', int(sys.argv[2]) if len(sys.argv) > 2 else 5149))
while True:
    data, (ip, _) = s.recvfrom(65536)
    if ip == '192.168.9.2':
        out.write(data)
        if out.tell() > CAP:
            out.close()
            os.replace(path, path + '.old')
            out = open(path, 'ab', buffering=0)
