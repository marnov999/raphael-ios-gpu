import re,sys,bisect,statistics,collections
t=open(sys.argv[1],'rb').read().decode('utf-8','replace')
b=t.rfind('TL begin'); e=t.find('TL end',b); seg=t[b:e]
ticks=sorted(int(x) for x in re.findall(r'TL v (\d+)',seg))
sw=[tuple(map(int,m)) for m in re.findall(r'TL s (\d+) (\d+) (\d+) (\d+) (\d+) (\d+) (\d+)',seg)]
P=statistics.median(b-a for a,b in zip(ticks,ticks[1:]))
def win(x): return bisect.bisect_right(ticks,x)-1
held=collections.Counter(); cls=collections.Counter()
sw=[x for x in sw if x[3]]          # (the flipped ones)
for k in range(1,len(sw)):
    a0,a1=sw[k-1],sw[k]
    if a1[1]-a0[1]>70000: continue
    s0=win(a0[3])+1; s1=win(a1[3])+1
    h=s1-s0
    if h<=0: continue
    held[h]+=1
    if h>=2:
        dw=win(a1[1])-win(a0[1])
        cls['CA skipped a tick' if dw>=2 else 'late flip']+=1
rep=sum((k-1)*n for k,n in held.items()); tot=sum(k*n for k,n in held.items())
print(sys.argv[1].split('prof_')[-1], 'by flip: held',sorted(held.items()),'repeats %.1f%%'%(100*rep/tot), dict(cls))
