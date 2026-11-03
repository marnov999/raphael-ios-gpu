#!/usr/bin/env python3
# Read a file back from the device via sweet_push MAGIC_RD. usage: read_file.py <devicepath> Mi 9T Pro copy of davinci-ios/gpu/userland/metal/read_file.py (raphael gadget: 192.168.9.x).
import socket, struct, sys
DEV=("192.168.9.2",5566); MAGIC_RD=0x53505244
p=sys.argv[1].encode()
s=socket.create_connection(DEV,timeout=20); s.settimeout(20)
s.sendall(struct.pack("<I",MAGIC_RD)); s.sendall(struct.pack("<I",len(p))); s.sendall(p)
hdr=b""
while len(hdr)<8: hdr+=s.recv(8-len(hdr))
n=struct.unpack("<Q",hdr)[0]
buf=b""
while len(buf)<n:
    c=s.recv(min(65536,n-len(buf)))
    if not c: break
    buf+=c
s.close()
sys.stdout.buffer.write(buf)
