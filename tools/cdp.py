#!/usr/bin/env python3
"""cdp.py: talk to a Chrome-DevTools-protocol inspector on the phone (Gameface/cohtml's, which Minecraft opens with
the option ore_ui_debugging:1 in options.txt). Plain sockets, no packages.

  tools/cdp.py scan [HOST] [FIRST LAST]       which TCP ports answer (default 192.168.9.2, 9000-9999)
  tools/cdp.py targets HOST:PORT              GET /json: the pages it offers
  tools/cdp.py eval HOST:PORT 'JS' [SECS]     attach to the first page, enable Runtime/Log, evaluate JS, then print
                                              console messages and exceptions for SECS (default 5)
"""
import base64, json, os, socket, struct, sys, time


def http_get(host, port, path):
    s = socket.create_connection((host, port), timeout=5)
    s.sendall(('GET %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\n\r\n' % (path, host, port)).encode())
    data = b''
    while True:
        b = s.recv(65536)
        if not b:
            break
        data += b
    s.close()
    head, _, body = data.partition(b'\r\n\r\n')
    return head.decode('latin1'), body


class WS:
    def __init__(self, host, port, path):
        self.s = socket.create_connection((host, port), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(('GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                        'Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n' % (path, host, port, key)).encode())
        resp = b''
        while b'\r\n\r\n' not in resp:
            resp += self.s.recv(4096)
        if b' 101 ' not in resp.split(b'\r\n')[0]:
            raise RuntimeError('no websocket: ' + resp.split(b'\r\n')[0].decode('latin1'))
        self.buf = resp.split(b'\r\n\r\n', 1)[1]
        self.n = 0

    def send(self, method, params=None):
        self.n += 1
        msg = json.dumps({'id': self.n, 'method': method, 'params': params or {}}).encode()
        mask = os.urandom(4)
        hdr = bytes([0x81])
        ln = len(msg)
        if ln < 126:
            hdr += bytes([0x80 | ln])
        elif ln < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack('>H', ln)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack('>Q', ln)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(msg)))
        return self.n

    def _need(self, k):
        while len(self.buf) < k:
            b = self.s.recv(65536)
            if not b:
                raise EOFError
            self.buf += b

    def recv(self, timeout):
        self.s.settimeout(timeout)
        try:
            self._need(2)
        except socket.timeout:
            return None
        b0, b1 = self.buf[0], self.buf[1]
        ln, off = b1 & 0x7f, 2
        if ln == 126:
            self._need(4); ln = struct.unpack('>H', self.buf[2:4])[0]; off = 4
        elif ln == 127:
            self._need(10); ln = struct.unpack('>Q', self.buf[2:10])[0]; off = 10
        self._need(off + ln)
        payload, self.buf = self.buf[off:off + ln], self.buf[off + ln:]
        if b0 & 0x0f == 8:
            raise EOFError
        try:
            return json.loads(payload)
        except ValueError:
            return None


def main():
    cmd = sys.argv[1]
    if cmd == 'scan':
        host = sys.argv[2] if len(sys.argv) > 2 else '192.168.9.2'
        a, b = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (9000, 9999)
        for p in range(a, b + 1):
            s = socket.socket()
            s.settimeout(0.05)
            if s.connect_ex((host, p)) == 0:
                print('open', p)
            s.close()
        return
    host, port = sys.argv[2].rsplit(':', 1)
    port = int(port)
    if cmd == 'targets':
        print(http_get(host, port, '/json')[1].decode('utf-8', 'replace'))
        return
    if cmd == 'eval':
        targets = json.loads(http_get(host, port, '/json')[1] or b'[]')
        ws_url = targets[0]['webSocketDebuggerUrl'] if targets else '/devtools/page/1'
        path = '/' + ws_url.split('://', 1)[-1].split('/', 1)[-1] if '://' in ws_url else ws_url
        w = WS(host, port, path)
        w.send('Runtime.enable'); w.send('Log.enable')
        eid = w.send('Runtime.evaluate', {'expression': sys.argv[3], 'returnByValue': True})
        end = time.time() + (float(sys.argv[4]) if len(sys.argv) > 4 else 5)
        while time.time() < end:
            m = w.recv(max(0.1, end - time.time()))
            if m is None:
                continue
            meth = m.get('method', '')
            if m.get('id') == eid:
                print('RESULT', json.dumps(m.get('result', m.get('error')))[:4000])
            elif meth == 'Runtime.consoleAPICalled':
                p = m['params']
                print('CONSOLE', p.get('type'), ' '.join(str(a.get('value', a.get('description', ''))) for a in p.get('args', [])))
            elif meth == 'Runtime.exceptionThrown':
                d = m['params']['exceptionDetails']
                print('EXCEPTION', d.get('text'), (d.get('exception') or {}).get('description', '')[:2000])
            elif meth == 'Log.entryAdded':
                e = m['params']['entry']
                print('LOG', e.get('level'), e.get('text'))
        return
    sys.exit(__doc__)


if __name__ == '__main__':
    main()
