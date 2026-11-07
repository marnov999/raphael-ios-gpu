#!/system/bin/sh
# bench60-miui.sh OUT (on MIUI, as root; pushed by tools/bench-miui.sh): bench81.sh's gestures on MIUI with an
# ftrace of every frame and clock change. The real touchscreen must be held already (ghost touches):
# `atouch -g "sleep N"` in the background. Home page 1 must hold the launcher's start; Settings is on page 2.
OUT=${1:?out}
T=/sys/kernel/tracing
AT=/data/local/tmp/atouch
EV="power/gpu_frequency kgsl/kgsl_pwrlevel kgsl/kgsl_buslevel power/bw_hwmon_update power/memlat_dev_update power/cpu_frequency_limits"
# the screen on and unlocked (no lock code), kept on for the bench (the setting put back after)
STAY=$(settings get global stay_on_while_plugged_in)
settings put global stay_on_while_plugged_in 7
$AT "key 143" "sleep 600"
wm dismiss-keyguard
sleep 1
atrace --async_start -b 32768 -c gfx view input freq >/dev/null
for e in $EV; do echo 1 > $T/events/$e/enable; done
# the clocks at the start (the trace has only their changes)
S="start"
for p in 0 4 7; do S="$S cpu$p=$(cat /sys/devices/system/cpu/cpufreq/policy$p/scaling_cur_freq)"; done
S="$S gpu=$(cat /sys/class/kgsl/kgsl-3d0/gpuclk)"
for d in /sys/class/devfreq/*; do S="$S $(basename $d)=$(cat $d/cur_freq 2>/dev/null)"; done
echo "atouch: clocks $S" > $T/trace_marker
$AT "tap 540 2275" "sleep 4000" \
	"mark home begin" \
	"swipe 950 1300 150 1300 250" "sleep 700" "swipe 150 1300 950 1300 250" "sleep 700" \
	"swipe 950 1300 150 1300 250" "sleep 700" "swipe 150 1300 950 1300 250" "sleep 700" \
	"swipe 950 1300 150 1300 250" "sleep 700" "swipe 150 1300 950 1300 250" "sleep 700" \
	"mark home end" "sleep 1500" \
	"swipe 950 1300 150 1300 250" "sleep 2000" \
	"mark settings begin" \
	"tap 160 1130" "sleep 1500" "tap 540 2275" "sleep 1500" \
	"tap 160 1130" "sleep 1500" "tap 540 2275" "sleep 1500" \
	"tap 160 1130" "sleep 1500" "tap 540 2275" "sleep 1500" \
	"mark settings end" "tap 540 2275" "sleep 500"
atrace --async_dump -o "$OUT" >/dev/null
atrace --async_stop >/dev/null
for e in $EV; do echo 0 > $T/events/$e/enable; done
settings put global stay_on_while_plugged_in "$STAY"
echo "bench60-miui: $OUT $(wc -c < "$OUT") bytes"
