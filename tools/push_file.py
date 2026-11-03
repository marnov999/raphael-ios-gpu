#!/usr/bin/env python3
# Host-side sender for sweet_push (device 192.168.9.2:5566). Mi 9T Pro copy of davinci-ios/gpu/userland/metal/push_file.py (raphael gadget: 192.168.9.x).
# usage: push_file.py <localfile> <devicepath> [mode_octal]
#   mode with any exec bit -> device auto-spawns it after write.
import socket, struct, sys, os
DEV=("192.168.9.2",5566); MAGIC=0x53505348
def push(local,dev,mode):
    data=open(local,"rb").read()
    p=dev.encode()
    s=socket.create_connection(DEV,timeout=20+len(data)//100000)
    s.sendall(struct.pack("<I",MAGIC))
    s.sendall(struct.pack("<I",len(p))); s.sendall(p)
    s.sendall(struct.pack("<I",mode)); s.sendall(struct.pack("<Q",len(data)))
    s.sendall(data)
    s.settimeout(20)
    try: r=s.recv(1)
    except Exception: r=b""
    s.close()
    print(f"[push] {local} -> {dev} ({len(data)} bytes, mode {oct(mode)}) ack={r!r}")
if __name__=="__main__":
    local=sys.argv[1]; dev=sys.argv[2]
    mode=int(sys.argv[3],8) if len(sys.argv)>3 else (0o755 if os.access(local,os.X_OK) else 0o644)
    push(local,dev,mode)
