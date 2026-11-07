/*
 * cahook (raphael, 2026-11-03): when CoreAnimation's render server (backboardd) gets each vsync, when it
 * renders and for what time, and when each client's commit comes in -- to see why, at 81 Hz, it leaves
 * ~4% of the panel's refreshes with no new frame (a tick with nothing drawn, its vsync not lost).
 * Inline hooks on shared-cache functions (QuartzCore of iOS 16.7, as hooktrace does): each call is a
 * timestamped event in a ring; ch_dump() prints them as "tl: h" lines (the GL bridge, after each frame).
 * On with /usr/local/gltest/gl_cahook.
 */
#include <dlfcn.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>

extern uint32_t ch_tramp_0[], ch_tramp_1[], ch_tramp_2[], ch_tramp_3[], ch_tramp_4[], ch_tramp_5[], ch_tramp_6[],
    ch_tramp_7[], ch_tramp_8[], ch_tramp_9[], ch_tramp_10[], ch_tramp_11[];      /* cahook.S */
extern uint64_t ch_back[];              /* where each trampoline goes on: the function past its head */
extern char ch_stub_0[], ch_stub_1[], ch_stub_2[], ch_stub_3[], ch_stub_4[], ch_stub_5[], ch_stub_6[], ch_stub_7[], ch_stub_8[],
    ch_stub_9[], ch_stub_10[], ch_stub_11[];

/* the functions, by their address in the shared cache (and the probe the slide is had from) */
#define CH_PROBE                0x1882c1cc4ull  /* CACurrentMediaTime */
static const struct {
	const char *name;
	uint64_t addr;
	int set;                        /* 0: the window server's (backboardd), 1: a program's (SpringBoard) */
} ch_targets[] = {
	{ "IOMFBServer::vsync_callback", 0x1882ba1ecull, 0 },           /* 0: (fb, ...) the vsync from the framebuffer */
	{ "IOMFBServer::timer_callback", 0x188350b24ull, 0 },           /* 1: (CADisplayTimer, ...) */
	{ "Server::timer_callback", 0x1883a430cull, 0 },                /* 2: (double, void *) */
	{ "Server::render_for_time", 0x1884f4df0ull, 0 },               /* 3: (this, double time, ...) */
	{ "Render::Context::will_commit", 0x188413780ull, 0 },          /* 4: (context) */
	{ "Render::Context::did_commit", 0x188413934ull, 0 },           /* 5: (context, bool, double, bool) */
	{ "Display::DisplayLink::callback", 0x1882bf500ull, 1 },        /* 6: (timer, u64, u64, u64, info) */
	{ "Display::DisplayLink::dispatch_items", 0x1882ab35cull, 1 },  /* 7: (this, u64, u64, u64) */
	{ "Transaction::commit", 0x1882ddb3cull, 1 },                   /* 8: (this) */
	{ "Context::commit_transaction", 0x1882b0828ull, 1 },           /* 9: (this, transaction, double, double *) */
	{ "DisplayLinkItem::set_preferred_fps_range", 0x18831d1c4ull, 1 }, /* 10: (this, CAFrameRateRange s0-s2, bool, bool) */
	{ "DynamicFrameRateSource::set_preferred_fps_range", 0x1884421acull, 1 }, /* 11: (this, CAFrameRateRange, bool) */
};
#define CH_PROCESS_ID           0x1882ce26cull  /* CA::Render::Context::process_id() const */
#define CH_N (sizeof(ch_targets) / sizeof(ch_targets[0]))

struct ch_event {
	uint64_t t;
	uint32_t id, a;
	double d;
	float f[3];                     /* (10, 11: the frame rate range asked for, minimum, maximum, preferred) */
};
#define CH_RING 8192u
static struct ch_event ch_ring[CH_RING];
static volatile uint32_t ch_head, ch_tail;
static int (*ch_pid_of)(void *context);

/*
 * (2026-11-07) The frame rates SpringBoard's animations ask for, scaled by ch_fps_scale (the panel's rate over 60:
 * 1.35 at 81 Hz; /usr/local/gltest/gl_sb_fps, 0 = as asked). CoreAnimation runs a display link at the panel's rate
 * over a whole number: a "30 fps" animation is every 2nd refresh at 60 Hz, but at 81 Hz the 40.5 is over its 30,
 * so it got 27 -- every 3rd refresh, a frame up 37 ms. Scaled, every request picks the divisor a 60 Hz iPhone
 * would (30 -> 40.5, 60 or 48..120 -> 81).
 */
static float ch_fps_scale;

void ch_log(long id, uint64_t x0, uint64_t x1, double d0, double d1, double d2, double *saved);
void
ch_log(long id, uint64_t x0, uint64_t x1, double d0, double d1, double d2, double *saved)
{
	if ((id == 10 || id == 11) && ch_fps_scale > 0 && saved != NULL) {
		for (int k = 0; k < 3; k++) {           /* s0..s2: the low halves of the saved d0..d2 */
			float f;
			memcpy(&f, &saved[k], 4);
			f *= ch_fps_scale;
			memcpy(&saved[k], &f, 4);
		}
	}
	uint32_t i = __atomic_fetch_add(&ch_head, 1u, __ATOMIC_RELAXED);
	struct ch_event *e = &ch_ring[i % CH_RING];
	e->t = mach_absolute_time();
	e->id = (uint32_t)id;
	if ((id == 4 || id == 5) && ch_pid_of != NULL && x0 != 0) {
		e->a = (uint32_t)ch_pid_of((void *)x0);         /* the client whose commit it is */
	} else if (id >= 6) {
		e->a = (uint32_t)pthread_mach_thread_np(pthread_self());        /* (a program's: which thread) */
	} else {
		e->a = (uint32_t)x1;
	}
	e->d = d0;
	if (id == 10 || id == 11) {             /* floats in s0..s2: the low halves of d0..d2 */
		memcpy(&e->f[0], &d0, 4);
		memcpy(&e->f[1], &d1, 4);
		memcpy(&e->f[2], &d2, 4);
	}
}

static int
ch_patch(void *where, const void *bytes, size_t n)
{
	vm_address_t page = (vm_address_t)where & ~0x3fffUL;
	vm_size_t len = (((vm_address_t)where + n + 0x3fff) & ~0x3fffUL) - page;
	if (vm_protect(mach_task_self(), page, len, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) {
		return -1;
	}
	memcpy(where, bytes, n);
	vm_protect(mach_task_self(), page, len, 0, VM_PROT_READ | VM_PROT_EXECUTE);
	sys_icache_invalidate(where, n);
	return 0;
}

/* Hooks what it can; returns how many, and says which not. */
int
ch_install(void (*say)(const char *, ...), int set)
{
	static char *stubs[] = { ch_stub_0, ch_stub_1, ch_stub_2, ch_stub_3, ch_stub_4, ch_stub_5, ch_stub_6, ch_stub_7, ch_stub_8,
		ch_stub_9, ch_stub_10, ch_stub_11 };
	static uint32_t *tramps[] = { ch_tramp_0, ch_tramp_1, ch_tramp_2, ch_tramp_3, ch_tramp_4, ch_tramp_5, ch_tramp_6, ch_tramp_7,
		ch_tramp_8, ch_tramp_9, ch_tramp_10, ch_tramp_11 };
	unsigned wanted = 0;
	void *probe = dlsym(RTLD_DEFAULT, "CACurrentMediaTime");
	int ok = 0;
	if (probe == NULL) {
		say("cahook: no CACurrentMediaTime\n");
		return 0;
	}
	intptr_t slide = (intptr_t)probe - (intptr_t)CH_PROBE;
	ch_pid_of = (int (*)(void *))(CH_PROCESS_ID + slide);
	for (unsigned i = 0; i < CH_N; i++) {
		if (ch_targets[i].set != set) {
			continue;
		}
		wanted++;
		uint32_t *code = (uint32_t *)(ch_targets[i].addr + slide), h[4] = { 0x58000050, 0xd61f0200 };
		if (memcmp(code, tramps[i], 16) != 0) {
			say("cahook: %s: not the instructions expected (%08x %08x), not hooked\n", ch_targets[i].name, code[0], code[1]);
			continue;
		}
		uint64_t stub = (uint64_t)stubs[i];
		ch_back[i] = (uint64_t)code + 16;
		memcpy(&h[2], &stub, 8);
		if (ch_patch(code, h, sizeof(h)) != 0) {
			say("cahook: %s: head not written\n", ch_targets[i].name);
			continue;
		}
		ok++;
	}
	say("cahook: slide %#lx, %d of %u hooked (set %d)\n", (long)slide, ok, wanted, set);
	return ok;
}

/* The events since the last dump: "tl: h ID:US:A:D ..." (US as the GL bridge's now_us, D the double argument) */
void
ch_dump(void (*say)(const char *, ...))
{
	static mach_timebase_info_data_t tb;
	char line[1024];
	int n = 0;
	uint32_t head = __atomic_load_n(&ch_head, __ATOMIC_ACQUIRE);
	if (tb.denom == 0) {
		mach_timebase_info(&tb);
	}
	if (head - ch_tail > CH_RING) {
		ch_tail = head - CH_RING;
	}
	for (; ch_tail != head; ch_tail++) {
		const struct ch_event *e = &ch_ring[ch_tail % CH_RING];
		if (n == 0) {
			n = snprintf(line, sizeof(line), "tl: h");
		}
		if (e->id == 10 || e->id == 11) {
			n += snprintf(line + n, sizeof(line) - (size_t)n, " %u:%llu:%u:%g/%g/%g", e->id,
			    (unsigned long long)(e->t * tb.numer / tb.denom / 1000ull), e->a, e->f[0], e->f[1], e->f[2]);
		} else {
			n += snprintf(line + n, sizeof(line) - (size_t)n, " %u:%llu:%u:%.6f", e->id,
			    (unsigned long long)(e->t * tb.numer / tb.denom / 1000ull), e->a, e->d);
		}
		if (n > 900) {
			say("%s\n", line);
			n = 0;
		}
	}
	if (n > 0) {
		say("%s\n", line);
	}
}

#if defined(CAHOOK_STANDALONE)
/*
 * libcahook.dylib: the same, in a program (SpringBoard, put in by sweet_shim with /usr/local/gltest/gl_cahook_sb
 * saying 1): when its display links fire and when it commits; "tl: h" lines to the host's UDP 5151 every 200 ms.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>

static int ch_sock = -1;
static char ch_name[32];

static void
ch_say(const char *format, ...)
{
	char line[1100];
	int n = snprintf(line, sizeof(line), "|%s| ", ch_name);
	va_list ap;
	va_start(ap, format);
	n += vsnprintf(line + n, sizeof(line) - (size_t)n, format, ap);
	va_end(ap);
	if (ch_sock >= 0 && n > 0) {
		(void)send(ch_sock, line, (size_t)(n < (int)sizeof(line) ? n : (int)sizeof(line) - 1), 0);
	}
}

static void *
ch_dumper(void *arg)
{
	(void)arg;
	for (;;) {
		usleep(200000);
		ch_dump(ch_say);
	}
	return NULL;
}

__attribute__((constructor)) static void
ch_standalone(void)
{
	char on = 0;
	int fd = open("/usr/local/gltest/gl_cahook_sb", O_RDONLY);
	if (fd < 0) {
		return;
	}
	if (read(fd, &on, 1) != 1 || on != '1') {
		close(fd);
		return;
	}
	close(fd);
	fd = open("/usr/local/gltest/gl_sb_fps", O_RDONLY);
	if (fd >= 0) {
		char b[16] = { 0 };
		if (read(fd, b, sizeof(b) - 1) > 0) {
			ch_fps_scale = strtof(b, NULL);
		}
		close(fd);
	}
	snprintf(ch_name, sizeof(ch_name), "%s", getprogname());
	ch_sock = socket(AF_INET, SOCK_DGRAM, 0);
	if (ch_sock >= 0) {
		struct sockaddr_in a;
		memset(&a, 0, sizeof(a));
		a.sin_family = AF_INET;
		a.sin_port = htons(5151);
		a.sin_addr.s_addr = inet_addr("192.168.9.1");
		if (connect(ch_sock, (struct sockaddr *)&a, sizeof(a)) != 0) {
			close(ch_sock);
			ch_sock = -1;
		}
	}
	ch_say("cahook: frame rate requests scaled by %g (gl_sb_fps)\n", (double)ch_fps_scale);
	if (ch_install(ch_say, 1) > 0) {
		pthread_t t;
		pthread_create(&t, NULL, ch_dumper, NULL);
	}
}
#endif
