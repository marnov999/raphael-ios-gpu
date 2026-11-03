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
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uint32_t ch_tramp_0[], ch_tramp_1[], ch_tramp_2[], ch_tramp_3[], ch_tramp_4[], ch_tramp_5[];    /* cahook.S */
extern uint64_t ch_back[];              /* where each trampoline goes on: the function past its head */
extern char ch_stub_0[], ch_stub_1[], ch_stub_2[], ch_stub_3[], ch_stub_4[], ch_stub_5[];

/* the functions, by their address in the shared cache (and the probe the slide is had from) */
#define CH_PROBE                0x1882c1cc4ull  /* CACurrentMediaTime */
static const struct {
	const char *name;
	uint64_t addr;
} ch_targets[] = {
	{ "IOMFBServer::vsync_callback", 0x1882ba1ecull },              /* 0: (fb, ...) the vsync from the framebuffer */
	{ "IOMFBServer::timer_callback", 0x188350b24ull },              /* 1: (CADisplayTimer, ...) */
	{ "Server::timer_callback", 0x1883a430cull },                   /* 2: (double, void *) */
	{ "Server::render_for_time", 0x1884f4df0ull },                  /* 3: (this, double time, ...) */
	{ "Render::Context::will_commit", 0x188413780ull },             /* 4: (context) */
	{ "Render::Context::did_commit", 0x188413934ull },              /* 5: (context, bool, double, bool) */
};
#define CH_PROCESS_ID           0x1882ce26cull  /* CA::Render::Context::process_id() const */
#define CH_N (sizeof(ch_targets) / sizeof(ch_targets[0]))

struct ch_event {
	uint64_t t;
	uint32_t id, a;
	double d;
};
#define CH_RING 8192u
static struct ch_event ch_ring[CH_RING];
static volatile uint32_t ch_head, ch_tail;
static int (*ch_pid_of)(void *context);

void ch_log(long id, uint64_t x0, uint64_t x1, double d0);
void
ch_log(long id, uint64_t x0, uint64_t x1, double d0)
{
	uint32_t i = __atomic_fetch_add(&ch_head, 1u, __ATOMIC_RELAXED);
	struct ch_event *e = &ch_ring[i % CH_RING];
	e->t = mach_absolute_time();
	e->id = (uint32_t)id;
	e->a = (id == 4 || id == 5) && ch_pid_of != NULL && x0 != 0 ? (uint32_t)ch_pid_of((void *)x0) : (uint32_t)x1;
	e->d = d0;
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
ch_install(void (*say)(const char *, ...))
{
	static char *stubs[] = { ch_stub_0, ch_stub_1, ch_stub_2, ch_stub_3, ch_stub_4, ch_stub_5 };
	static uint32_t *tramps[] = { ch_tramp_0, ch_tramp_1, ch_tramp_2, ch_tramp_3, ch_tramp_4, ch_tramp_5 };
	void *probe = dlsym(RTLD_DEFAULT, "CACurrentMediaTime");
	int ok = 0;
	if (probe == NULL) {
		say("cahook: no CACurrentMediaTime\n");
		return 0;
	}
	intptr_t slide = (intptr_t)probe - (intptr_t)CH_PROBE;
	ch_pid_of = (int (*)(void *))(CH_PROCESS_ID + slide);
	for (unsigned i = 0; i < CH_N; i++) {
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
	say("cahook: slide %#lx, %d of %u hooked\n", (long)slide, ok, (unsigned)CH_N);
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
		n += snprintf(line + n, sizeof(line) - (size_t)n, " %u:%llu:%u:%.6f", e->id,
		    (unsigned long long)(e->t * tb.numer / tb.denom / 1000ull), e->a, e->d);
		if (n > 900) {
			say("%s\n", line);
			n = 0;
		}
	}
	if (n > 0) {
		say("%s\n", line);
	}
}
