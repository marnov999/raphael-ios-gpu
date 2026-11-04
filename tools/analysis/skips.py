#!/usr/bin/env python3
"""skips.py PROF SPRINGBOARD_LOG: why each panel refresh of an animation showed no new frame.

PROF: a tools/measure.sh profile of backboardd (kernel TL timeline + the GL bridge's "tl: h" events, cahook);
SPRINGBOARD_LOG: libcahook's "tl: h" lines from SpringBoard (UDP 5151) over the same time. Classes:
  no change      SpringBoard's display link fired, it committed nothing (an animation's still tail): not seen
  late           it committed after the vsync the frame was for
  server         its commit was in time, the window server's frame was not (render, GPU)
  no link        no SpringBoard display link in that period (another program's frame, or vsync just turned on)
Ends with a SUMMARY line.
"""
import re,sys,bisect,statistics,collections
t=open(sys.argv[1],'rb').read().decode('utf-8','replace')
sb=open(sys.argv[2],'rb').read().decode('utf-8','replace')
b=t.rfind('TL begin'); e=t.find('TL end',b); seg=t[b:e]
ticks=sorted(int(x) for x in re.findall(r'TL v (\d+)',seg))
sw=[tuple(map(int,m)) for m in re.findall(r'TL s (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)',seg)]
def parse(text,src):
    raw=text.replace('|backboardd| ','')
    out=[]
    for line in raw.split('\n'):
        if 'tl: h' not in line: continue
        for m in re.finditer(r'\b([0-9]):(\d{6,}):(\d+):(-?[\d.]+)',line[line.index('tl: h'):]):
            out.append((int(m.group(2)),int(m.group(1)),int(m.group(3)),float(m.group(4)),src))
    return out
ev=sorted(parse(t,'B')+parse(sb,'S'))
lo,hi=ticks[0],ticks[-1]; ev=[x for x in ev if lo-20000<x[0]<hi]
print('events',collections.Counter((x[4],x[1]) for x in ev))
# SpringBoard main thread = most common thread of id 8 (Transaction::commit)
main=collections.Counter(x[2] for x in ev if x[1]==8).most_common(3); print('commit threads',main)
names={0:'vsync',3:'render',5:'did_commit',6:'SB-link-cb',7:'SB-dispatch',8:'SB-tx-commit',9:'SB-ctx-commit'}
P=statistics.median(b2-a for a,b2 in zip(ticks,ticks[1:]))
def win(x): return bisect.bisect_right(ticks,x)-1
skips=[]
# a refresh that showed no new frame: two swaps of an animation whose flips (sw[3]) were 2+ ticks apart on the
# panel (with sweetfb_drawtick a frame that came late can still be shown in time); the period it belongs to is
# the one after the earlier swap came
# (only the swaps that were flipped: one drawn again in the same tick -- sweetfb_retick -- replaces the other)
fl=[x for x in sw if x[3]]
for k in range(1,len(fl)):
    a0,a1=fl[k-1],fl[k]
    if a1[1]-a0[1]>=70000: continue
    if win(a1[3])-win(a0[3])>=2: skips.append(win(a0[1])+1)
def show(i,label):
    T=ticks[i]; out=[]; prev=None
    for x in ev:
        if not (T-1.0*P<x[0]<T+1.1*P): continue
        if x[1] in (1,2,4): continue
        n=names.get(x[1],str(x[1]))
        if x[1]==5 and x[2]!=main[0][0] and False: pass
        key=n
        if key==prev: continue
        prev=key
        out.append('%+.1f %s'%((x[0]-T)/1000,n))
    print(label,i,': ',' | '.join(out))
norm=[i for i in range(60,len(ticks)) if i not in skips][:2]
for i in norm: show(i,'normal')
for i in skips[:10]: show(i,'SKIP')
# per SB link callback: time from callback to its tx commit
cb=[x[0] for x in ev if x[1]==6]; tx=sorted(x[0] for x in ev if x[1]==8)
lat=[]
for c in cb:
    j=bisect.bisect_left(tx,c)
    if j<len(tx) and tx[j]-c<40000: lat.append((tx[j]-c)/1000)
lat.sort()
if lat: print('SB link callback -> next Transaction::commit: median %.1f ms p90 %.1f p99 %.1f max %.1f (n %d)'%(statistics.median(lat),lat[int(.9*len(lat))],lat[int(.99*len(lat))],lat[-1],len(lat)))
# phase of SB link callbacks vs ticks
ph=collections.Counter(int((c-ticks[win(c)])/1000) for c in cb if win(c)>=0)
print('SB link callback phase after tick:',sorted(ph.items()))
print('---- skip classes')
link=sorted(x[0] for x in ev if x[1]==6); txs=sorted(x[0] for x in ev if x[1]==8)
cls=collections.Counter(); late=[]
for i in skips:
    T=ticks[i]; prevT=ticks[i-1]
    lk=[c for c in link if prevT<=c<T]
    if not lk: cls['no SpringBoard display link in the period']+=1; continue
    c=lk[-1]
    tx=[x for x in txs if c<=x<c+P]
    if not tx: cls['link fired, nothing committed (no change)']+=1
    elif tx[0]>=T: cls['committed after the vsync (late)']+=1; late.append((tx[0]-c)/1000)
    else: cls['committed in time (server side)']+=1
print(dict(cls)); print('late commits: callback->commit ms',sorted(late))
print('SUMMARY frames %d late %d server %d nolink %d nochange %d'%(len([1 for k in range(1,len(fl)) if fl[k][1]-fl[k-1][1]<70000]),cls['committed after the vsync (late)'],cls['committed in time (server side)'],cls['no SpringBoard display link in the period'],cls['link fired, nothing committed (no change)']))
frames=len([1 for k in range(1,len(sw)) if sw[k][1]-sw[k-1][1]<70000])
print('animation frames',frames,'real misses %.1f%%'%(100*cls['committed after the vsync (late)']/max(1,frames)))
print('---- in-time-but-skipped detail')
dc=sorted(x[0] for x in ev if x[1]==5 and x[2]==sbpid) if False else None
sbpids=collections.Counter(x[2] for x in ev if x[1]==5).most_common(1)
sbp=sbpids[0][0]
dcs=sorted(x[0] for x in ev if x[1]==5 and x[2]==sbp)
rnd=sorted(x[0] for x in ev if x[1]==3)
vsy=sorted(x[0] for x in ev if x[1]==0)
for i in skips:
    T=ticks[i]; prevT=ticks[i-1]
    lk=[c for c in link if prevT<=c<T]
    if not lk: continue
    c=lk[-1]
    tx=[x for x in txs if c<=x<c+P]
    if not tx or tx[0]>=T: continue
    d=[x for x in dcs if tx[0]<=x<tx[0]+P]
    v=[x for x in vsy if T-3000<=x<T+3000]
    r=[x for x in rnd if T-3000<=x<T+3000]
    print('tick %d: link %+.2f tx %+.2f server did_commit %s vsync-cb %s render %s'%(i,(c-T)/1000,(tx[0]-T)/1000,['%+.2f'%((x-T)/1000) for x in d[:3]],['%+.2f'%((x-T)/1000) for x in v],['%+.2f'%((x-T)/1000) for x in r]))
print('---- server-side: render start -> swap arrival, slow calls')
gfr=sorted((int(m[1]),int(m[2]),int(m[0])) for m in re.findall(r'tl: g (\d+) began (\d+) ended (\d+) (\d+) end (\d+) waited (\d+)',t))
slowc=sorted((int(m.group(3)),m.group(1),int(m.group(2))) for m in re.finditer(r'tl: slow[- ](\S+) (\d+) at (\d+)',t))
arr=sorted(s_[1] for s_ in sw)
for i in skips:
    T=ticks[i]; prevT=ticks[i-1]
    lk=[c for c in link if prevT<=c<T]
    if not lk: continue
    c=lk[-1]; tx=[x for x in txs if c<=x<c+P]
    if not tx or tx[0]>=T: continue
    r=[x for x in rnd if T-3000<=x<T+3000]
    if not r: print('tick',i,'no render near the vsync'); continue
    a=[x for x in arr if x>r[0]][:1]
    g=[x for x in gfr if r[0]<=x[0]<r[0]+30000][:2]
    sl=[(x[1],x[2]//1000,(x[0]-T)//1000) for x in slowc if T-2000<x[0]<T+30000]
    print('tick %d: render %+.1f, GL frame %s, swap %+.1f; slow %s'%(i,(r[0]-T)/1000,['%+.1f..%+.1f'%((x[0]-T)/1000,(x[1]-T)/1000) for x in g],((a[0]-T)/1000 if a else -1),sl))
