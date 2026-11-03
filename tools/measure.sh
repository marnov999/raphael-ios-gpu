#!/bin/bash
# measure.sh NAME SECS PROCESS -- TOUCH LINES... (Mi 9T Pro copy of devtools/measure.sh): start the kernel's
# profile (+ frame timeline) of PROCESS for SECS, wait until the kernel says it began, inject the touches
# (tools/touch.sh); when it is done, print the frame statistics (inside animations) and thread times.
# LOG= the USB log file tools/usblog.py writes (default out/logs/u4-usb.log).
set -uo pipefail
cd "$(dirname "$0")/.."
NAME=$1; SECS=$2; PROC=$3; shift 4
LOG=${LOG:-out/logs/u4-usb.log}
S=/tmp/claude-1000/-home-marnov-xmiphones/9c49bc3f-61eb-47a2-b259-56d8036445a1/scratchpad
M=$(wc -c < "$LOG")
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
echo "$SECS $PROC $(date +%s%N)" > "$tmp"; python3 -I tools/push_file.py "$tmp" /tmp/prof_go 0644 >/dev/null
timeout 10 bash -c "until tail -c +$M '$LOG' | strings | grep -q 'PRF asked'; do sleep 0.3; done"
tools/touch.sh "$@"
timeout $((SECS + 120)) bash -c "until tail -c +$M '$LOG' | strings | grep -aq 'PRF end'; do sleep 2; done"
tail -c +$M "$LOG" | strings > $S/prof_last.txt
cp $S/prof_last.txt $S/prof_$NAME.txt
python3 - "$NAME" "$S/prof_last.txt" <<'PY'
import re,statistics,collections,bisect,sys
t=open(sys.argv[2],'rb').read().decode('utf-8','replace')
b=t.rfind('TL begin'); e=t.find('TL end',b); seg=t[b:e]
ticks=sorted(int(x) for x in re.findall(r'TL v (\d+)',seg))
arr=[int(m.group(2)) for m in re.finditer(r'TL s (\d+) (\d+)',seg)]
fr=[tuple(map(int,m)) for m in re.findall(r'tl: g (\d+) began (\d+) ended (\d+) (\d+) end (\d+) waited (\d+)',t)]
if len(arr)<10: print(sys.argv[1],': only',len(arr),'swaps'); sys.exit()
lo,hi=arr[0],arr[-1]; fr=[f for f in fr if lo<=f[1]<=hi]
iv=[(b2-a)/1000 for a,b2 in zip(arr,arr[1:])]
anim=sorted(x for x in iv if x<70)
p=lambda v,q: v[min(len(v)-1,int(len(v)*q))]
spans=collections.Counter(sum(1 for x in ticks if a<x<=b2) for a,b2 in zip(arr,arr[1:]) if b2-a<70000)
wake=sorted((f[1]-ticks[bisect.bisect_right(ticks,f[1])-1])/1000 for f in fr if bisect.bisect_right(ticks,f[1])>0)
gl=sorted((f[2]-f[1])/1000 for f in fr)
print(f'{sys.argv[1]}: {len(anim)} frames in animations: mean {statistics.mean(anim):.1f} ms ({1000/statistics.mean(anim):.1f} fps), median {statistics.median(anim):.1f} ms ({1000/statistics.median(anim):.1f} fps), p99 {p(anim,.99):.1f} ms ({1000/p(anim,.99):.1f} fps), p99.9 {p(anim,.999):.1f} ms ({1000/p(anim,.999):.1f} fps)')
# gaps between real animation frames only: both frames with 30+ draws (a still screen that updates now and then is no hitch)
fd={}
for f in fr:
    j=bisect.bisect_left(arr,f[2])
    if j<len(arr) and arr[j]-f[2]<5000: fd[j]=max(fd.get(j,0),f[3])
real=sorted((arr[j]-arr[j-1])/1000 for j in range(1,len(arr)) if fd.get(j,0)>=30 and fd.get(j-1,0)>=30 and arr[j]-arr[j-1]<200000)
if real: print(f'   between animation frames ({len(real)}): mean {statistics.mean(real):.1f} ms ({1000/statistics.mean(real):.1f} fps), median {statistics.median(real):.1f}, p99 {p(real,.99):.1f} ms ({1000/p(real,.99):.1f} fps), p99.9 {p(real,.999):.1f} ms ({1000/p(real,.999):.1f} fps)')
print(f'   ticks between swaps {sorted(spans.items())}; tick->first GL median {statistics.median(wake):.1f} p90 {p(wake,.9):.1f}; GL median {statistics.median(gl):.1f} p90 {p(gl,.9):.1f}')
# per frame: from the tick it started on to its swap -- over 16.7 ms it missed its slot ("janky", as Android counts)
work=[]
for f in fr:
    i=bisect.bisect_right(ticks,f[1])-1
    j=bisect.bisect_left(arr,f[2])
    if i>=0 and f[1]<=ticks[-1]+17000 and j<len(arr) and arr[j]-f[2]<5000: work.append((arr[j]-ticks[i])/1000)
work.sort()
if work: print(f'   frame time (tick -> swap): median {statistics.median(work):.1f} ms, p99 {p(work,.99):.1f} ms, p99.9 {p(work,.999):.1f} ms; missed the slot: {sum(1 for w in work if w>16.7)}/{len(work)} ({100*sum(1 for w in work if w>16.7)/len(work):.1f}%)')
# what the panel showed (ticks are on the panel's TEs, sweetfb_telock=1): each swap is on screen from the
# first tick after it; inside an animation (swaps under 70 ms apart) how many refreshes each new frame
# stayed up -- 1 is every refresh a new frame, 2+ a frame shown again (a stutter you see)
if len(ticks)>2:
    P=statistics.median(b2-a for a,b2 in zip(ticks,ticks[1:]))
    if work: print(f'   at the panel period {P/1000:.2f} ms: over a period tick -> swap: {sum(1 for w in work if w>P/1000)}/{len(work)} ({100*sum(1 for w in work if w>P/1000)/len(work):.1f}%)')
    shown=[]
    for a in arr:
        i=bisect.bisect_right(ticks,a+300)
        shown.append(ticks[i] if i<len(ticks) else None)
    held=collections.Counter(); ivs=[]
    for j in range(1,len(arr)):
        if shown[j] is None or shown[j-1] is None or arr[j]-arr[j-1]>=70000 or shown[j]==shown[j-1]: continue
        k=max(1,round((shown[j]-shown[j-1])/P)); held[k]+=1; ivs.append(k*P/1000)
    ivs.sort()
    if ivs:
        rep=sum((k-1)*n for k,n in held.items()); tot=sum(k*n for k,n in held.items())
        print(f'   shown: refreshes each animation frame stayed up {sorted(held.items())}; refreshes repeating a frame {rep}/{tot} ({100*rep/tot:.1f}%); shown interval median {statistics.median(ivs):.1f} ms ({1000/statistics.median(ivs):.1f} fps), p99 {p(ivs,.99):.1f} ms ({1000/p(ivs,.99):.1f} fps)')
busy=[(int(m.group(1)),int(m.group(2)),int(m.group(3))) for m in re.finditer(r'PRF t (\d+) (\d+) (\d+)',t)]
print('   busiest threads (% of a core):', ', '.join(f'{tid}:{pm/10:.0f}%' for tid,us,pm in sorted(busy,key=lambda x:-x[1])[:5]))
PY
