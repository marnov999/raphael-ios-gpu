/*
 * atouch (raphael MIUI, 2026-11-07): synthetic touches for the Android side, the counterpart of
 * userland/hidtouch.c (iOS), so the same frame-rate bench can run on MIUI.
 *
 *   atouch [-g] CMD [CMD ...]      each CMD one argument, in panel pixels (1080 x 2340):
 *       "tap X Y"
 *       "swipe X1 Y1 X2 Y2 MS"     a move every 4 ms on absolute deadlines (as hidtouch: a 240 Hz digitizer)
 *       "sleep MS"
 *       "mark TEXT"                a line in the ftrace buffer (trace_marker), to find it in the trace
 *       "key CODE"                 a key pressed and let go (Linux codes: 143 wakeup, 172 home, 158 back, 116 power)
 *   -g  holds the real touchscreen (goodix_ts, EVIOCGRAB) for the run: its ghost touches do not get in.
 *       The grab ends with the process, so the touchscreen is back afterwards.
 *
 * The touches come from a uinput multitouch device (protocol B, INPUT_PROP_DIRECT: Android takes it as a
 * touchscreen of the default display). Each gesture is also written to trace_marker ("atouch: ...").
 * No libc: built freestanding (tools/build-atouch.sh), so it runs on Android without the NDK.
 */
typedef unsigned long u64;
typedef long s64;
typedef unsigned int u32;
typedef int s32;
typedef unsigned short u16;

/* ---- syscalls (aarch64 Linux) ---- */
static long
sc(long n, long a, long b, long c, long d, long e)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;
	register long x4 __asm__("x4") = e;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4) : "memory");
	return x0;
}
#define SYS_ioctl 29
#define SYS_openat 56
#define SYS_close 57
#define SYS_write 64
#define SYS_exit_group 94
#define SYS_clock_nanosleep 115
#define SYS_sched_setscheduler 119
#define SYS_clock_gettime 113
#define AT_FDCWD (-100)
#define O_RDWR 2
#define O_WRONLY 1
#define O_NONBLOCK 04000

struct timespec { s64 sec, nsec; };

void *memset(void *d, int c, unsigned long n);
void *memcpy(void *d, const void *s, unsigned long n);
void *
memset(void *d, int c, unsigned long n)
{
	unsigned char *p = d;
	while (n--) {
		*p++ = (unsigned char)c;
	}
	return d;
}
void *
memcpy(void *d, const void *s, unsigned long n)
{
	unsigned char *p = d;
	const unsigned char *q = s;
	while (n--) {
		*p++ = *q++;
	}
	return d;
}
static unsigned long
slen(const char *s)
{
	unsigned long n = 0;
	while (s[n]) {
		n++;
	}
	return n;
}
static int
sneq(const char *a, const char *b, unsigned long n)
{
	for (unsigned long i = 0; i < n; i++) {
		if (a[i] != b[i]) {
			return 0;
		}
		if (!a[i]) {
			return 1;
		}
	}
	return 1;
}
static void
say(const char *s)
{
	sc(SYS_write, 2, (long)s, (long)slen(s), 0, 0);
}
static void
die(const char *s)
{
	say("atouch: ");
	say(s);
	say("\n");
	sc(SYS_exit_group, 1, 0, 0, 0, 0);
}
/* the numbers of a command, after its word */
static int
nums(const char *s, long *v, int max)
{
	int n = 0;
	while (*s && *s != ' ') {
		s++;
	}
	while (*s && n < max) {
		while (*s == ' ') {
			s++;
		}
		if (*s < '0' || *s > '9') {
			break;
		}
		long x = 0;
		while (*s >= '0' && *s <= '9') {
			x = x * 10 + (*s++ - '0');
		}
		v[n++] = x;
	}
	return n;
}

static s64
now_ns(void)
{
	struct timespec t;
	sc(SYS_clock_gettime, 1, (long)&t, 0, 0, 0);        /* CLOCK_MONOTONIC = ftrace's "mono" base */
	return t.sec * 1000000000L + t.nsec;
}
static void
sleep_until(s64 ns)
{
	struct timespec t = { ns / 1000000000L, ns % 1000000000L };
	while (sc(SYS_clock_nanosleep, 1, 1, (long)&t, 0, 0) != 0) {   /* TIMER_ABSTIME; again after a signal */
	}
}

/* ---- input ---- */
#define EV_SYN 0
#define EV_KEY 1
#define EV_ABS 3
#define BTN_TOOL_FINGER 0x145
#define BTN_TOUCH 0x14a
#define ABS_MT_SLOT 0x2f
#define ABS_MT_TOUCH_MAJOR 0x30
#define ABS_MT_POSITION_X 0x35
#define ABS_MT_POSITION_Y 0x36
#define ABS_MT_TRACKING_ID 0x39
#define IOC(dir, type, nr, size) (((u64)(dir) << 30) | ((u64)(size) << 16) | ((u64)(type) << 8) | (u64)(nr))
#define UI_SET_EVBIT IOC(1, 'U', 100, 4)
#define UI_SET_KEYBIT IOC(1, 'U', 101, 4)
#define UI_SET_ABSBIT IOC(1, 'U', 103, 4)
#define UI_SET_PROPBIT IOC(1, 'U', 110, 4)
#define UI_DEV_CREATE IOC(0, 'U', 1, 0)
#define UI_DEV_DESTROY IOC(0, 'U', 2, 0)
#define EVIOCGRAB IOC(1, 'E', 0x90, 4)
#define EVIOCGNAME(len) IOC(2, 'E', 0x06, len)

struct input_event { s64 sec, usec; u16 type, code; s32 value; };
struct uinput_user_dev {
	char name[80];
	u16 bustype, vendor, product, version;
	u32 ff_effects_max;
	s32 absmax[64], absmin[64], absfuzz[64], absflat[64];
};

static int ui = -1, marker = -1, tracking = 1;

static void
ev(u16 type, u16 code, s32 value)
{
	struct input_event e;
	memset(&e, 0, sizeof(e));
	e.type = type;
	e.code = code;
	e.value = value;
	sc(SYS_write, ui, (long)&e, sizeof(e), 0, 0);
}
static void
finger(int down, long x, long y)
{
	ev(EV_ABS, ABS_MT_SLOT, 0);
	if (down) {
		ev(EV_ABS, ABS_MT_TRACKING_ID, tracking);
		ev(EV_ABS, ABS_MT_POSITION_X, (s32)x);
		ev(EV_ABS, ABS_MT_POSITION_Y, (s32)y);
		ev(EV_ABS, ABS_MT_TOUCH_MAJOR, 8);
	} else {
		ev(EV_ABS, ABS_MT_TRACKING_ID, -1);
	}
	ev(EV_KEY, BTN_TOUCH, down);
	ev(EV_KEY, BTN_TOOL_FINGER, down);
	ev(EV_SYN, 0, 0);
}
static void
move(long x, long y)
{
	ev(EV_ABS, ABS_MT_SLOT, 0);
	ev(EV_ABS, ABS_MT_POSITION_X, (s32)x);
	ev(EV_ABS, ABS_MT_POSITION_Y, (s32)y);
	ev(EV_SYN, 0, 0);
}
static void
mark(const char *what)
{
	char line[200];
	unsigned long n = 0, w = slen(what);
	const char *p = "atouch: ";
	while (*p) {
		line[n++] = *p++;
	}
	if (w > sizeof(line) - n - 1) {
		w = sizeof(line) - n - 1;
	}
	memcpy(line + n, what, w);
	n += w;
	if (marker >= 0) {
		sc(SYS_write, marker, (long)line, (long)n, 0, 0);
	}
}

static int
open_touchscreen(void)
{
	char path[] = "/dev/input/event00", name[64];
	for (int i = 0; i < 32; i++) {
		int k = 16;
		if (i >= 10) {
			path[k++] = (char)('0' + i / 10);
		}
		path[k++] = (char)('0' + i % 10);
		path[k] = 0;
		int fd = (int)sc(SYS_openat, AT_FDCWD, (long)path, O_RDWR | O_NONBLOCK, 0, 0);
		if (fd < 0) {
			continue;
		}
		memset(name, 0, sizeof(name));
		if (sc(SYS_ioctl, fd, (long)EVIOCGNAME(sizeof(name) - 1), (long)name, 0, 0) > 0 && sneq(name, "goodix_ts", 10)) {
			return fd;
		}
		sc(SYS_close, fd, 0, 0, 0, 0);
	}
	return -1;
}

static void
setup(void)
{
	struct uinput_user_dev d;
	ui = (int)sc(SYS_openat, AT_FDCWD, (long)"/dev/uinput", O_WRONLY | O_NONBLOCK, 0, 0);
	if (ui < 0) {
		die("cannot open /dev/uinput (root?)");
	}
	sc(SYS_ioctl, ui, (long)UI_SET_EVBIT, EV_SYN, 0, 0);
	sc(SYS_ioctl, ui, (long)UI_SET_EVBIT, EV_KEY, 0, 0);
	sc(SYS_ioctl, ui, (long)UI_SET_EVBIT, EV_ABS, 0, 0);
	sc(SYS_ioctl, ui, (long)UI_SET_KEYBIT, BTN_TOUCH, 0, 0);
	sc(SYS_ioctl, ui, (long)UI_SET_KEYBIT, BTN_TOOL_FINGER, 0, 0);
	static const int keys[] = { 116, 143, 158, 172 };     /* KEY_POWER, KEY_WAKEUP, KEY_BACK, KEY_HOMEPAGE */
	for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
		sc(SYS_ioctl, ui, (long)UI_SET_KEYBIT, keys[i], 0, 0);
	}
	sc(SYS_ioctl, ui, (long)UI_SET_PROPBIT, 1 /* INPUT_PROP_DIRECT */, 0, 0);
	memset(&d, 0, sizeof(d));
	memcpy(d.name, "atouch", 7);
	d.bustype = 0x06;               /* BUS_VIRTUAL */
	d.vendor = 0x1234;
	d.product = 0x5678;
	d.version = 1;
	static const struct { int code, max; } axes[] = {
		{ ABS_MT_SLOT, 9 }, { ABS_MT_TOUCH_MAJOR, 255 }, { ABS_MT_POSITION_X, 1079 },
		{ ABS_MT_POSITION_Y, 2339 }, { ABS_MT_TRACKING_ID, 65535 },
	};
	for (unsigned i = 0; i < sizeof(axes) / sizeof(axes[0]); i++) {
		sc(SYS_ioctl, ui, (long)UI_SET_ABSBIT, axes[i].code, 0, 0);
		d.absmax[axes[i].code] = axes[i].max;
	}
	if (sc(SYS_write, ui, (long)&d, sizeof(d), 0, 0) != (long)sizeof(d) || sc(SYS_ioctl, ui, (long)UI_DEV_CREATE, 0, 0, 0) != 0) {
		die("uinput device not created");
	}
}

static void
run(const char *c)
{
	long v[8];
	int n = nums(c, v, 8);
	if (sneq(c, "tap ", 4) && n == 2) {
		mark(c);
		finger(1, v[0], v[1]);
		sleep_until(now_ns() + 60000000L);
		finger(0, 0, 0);
		tracking++;
	} else if (sneq(c, "swipe ", 6) && n == 5) {
		s64 t0 = now_ns(), dur = v[4] * 1000000L, step = 4000000L;
		mark(c);
		finger(1, v[0], v[1]);
		for (s64 t = step; t < dur; t += step) {
			sleep_until(t0 + t);
			move(v[0] + (v[2] - v[0]) * t / dur, v[1] + (v[3] - v[1]) * t / dur);
		}
		sleep_until(t0 + dur);
		move(v[2], v[3]);
		finger(0, 0, 0);
		tracking++;
	} else if (sneq(c, "key ", 4) && n == 1) {
		mark(c);
		ev(EV_KEY, (u16)v[0], 1);
		ev(EV_SYN, 0, 0);
		sleep_until(now_ns() + 40000000L);
		ev(EV_KEY, (u16)v[0], 0);
		ev(EV_SYN, 0, 0);
	} else if (sneq(c, "sleep ", 6) && n == 1) {
		sleep_until(now_ns() + v[0] * 1000000L);
	} else if (sneq(c, "mark ", 5)) {
		mark(c + 5);
	} else {
		say("atouch: what is \"");
		say(c);
		say("\"?\n");
	}
}

static int
amain(int argc, char **argv)
{
	int i = 1, grab = 0, ts = -1;
	if (i < argc && sneq(argv[i], "-g", 3)) {
		grab = 1;
		i++;
	}
	if (i >= argc) {
		die("usage: atouch [-g] \"tap X Y\" | \"swipe X1 Y1 X2 Y2 MS\" | \"sleep MS\" | \"mark TEXT\" ...");
	}
	struct { int policy_prio; } prio = { 50 };
	sc(SYS_sched_setscheduler, 0, 1 /* SCHED_FIFO */, (long)&prio, 0, 0);
	marker = (int)sc(SYS_openat, AT_FDCWD, (long)"/sys/kernel/tracing/trace_marker", O_WRONLY, 0, 0);
	if (marker < 0) {
		marker = (int)sc(SYS_openat, AT_FDCWD, (long)"/sys/kernel/debug/tracing/trace_marker", O_WRONLY, 0, 0);
	}
	if (grab) {
		ts = open_touchscreen();
		if (ts < 0 || sc(SYS_ioctl, ts, (long)EVIOCGRAB, 1, 0, 0) != 0) {
			die("the touchscreen (goodix_ts) not grabbed");
		}
	}
	setup();
	sleep_until(now_ns() + 700000000L);     /* InputReader takes the new device */
	for (; i < argc; i++) {
		run(argv[i]);
	}
	sleep_until(now_ns() + 100000000L);
	sc(SYS_ioctl, ui, (long)UI_DEV_DESTROY, 0, 0, 0);
	if (ts >= 0) {
		sc(SYS_ioctl, ts, (long)EVIOCGRAB, 0, 0, 0);
	}
	return 0;
}

/* entry: sp -> argc, argv[] */
__attribute__((used)) static void
cstart(long *sp)
{
	sc(SYS_exit_group, amain((int)sp[0], (char **)(sp + 1)), 0, 0, 0, 0);
}
__asm__(".globl _start\n_start:\n\tmov x0, sp\n\tbl cstart\n");
