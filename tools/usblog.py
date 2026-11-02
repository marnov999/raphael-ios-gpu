#!/usr/bin/env python3
"""usblog.py OUT.log [PORT]: write the Mi 9T Pro's live kernel console (xnu 0107: UDP from 192.168.9.2 to
port 5149 over USB ethernet, host connection enx02005e77ef01 = 192.168.9.1) to OUT.log as it arrives."""
import socket
import sys

out = open(sys.argv[1], 'ab', buffering=0)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('0.0.0.0', int(sys.argv[2]) if len(sys.argv) > 2 else 5149))
while True:
    data, (ip, _) = s.recvfrom(65536)
    if ip == '192.168.9.2':
        out.write(data)
