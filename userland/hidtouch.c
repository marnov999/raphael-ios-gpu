/*
 * hidtouch: synthetic touches into the HID event system (so a script can unlock, swipe, tap).
 * Commands from /tmp/touch_cmd, one per line, in panel pixels (1080 x 2340):
 *     tap X Y
 *     swipe X1 Y1 X2 Y2 MS        (MS: duration in milliseconds)
 *     sleep MS
 *     drag X0 Y0 X1 Y1 MS1 [X2 Y2 MS2 ...]   (one finger down at X0,Y0, through each point, then up)
 * Each touch is a hand event with one finger child, as the display's own digitizer sends them,
 * dispatched through an IOHIDEventSystemClient (needs com.apple.private.hid.client.event-dispatch).
 *
 * raphael's copy (2026-11-03): the moves come every STEP_US on absolute deadlines (mach_wait_until) from a
 * time-constraint thread. davinci's usleep(8000) is a timer of a background daemon, which the system may
 * coalesce: on an 81 Hz panel a finger that moves less often than the refreshes leaves frames with nothing
 * new (SpringBoard's pages follow the finger). The gaps between the moves are reported (stderr).
 */
#include <mach/mach.h>
#include <mach/thread_policy.h>
#define STEP_US 4000                    /* a move every 4 ms, as a 240 Hz digitizer */
#include <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
static IOHIDEventSystemClientRef client;
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef, IOHIDEventRef);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t type, uint32_t index,
    uint32_t identity, uint32_t eventMask, uint32_t buttonMask, double x, double y, double z, double pressure,
    double twist, Boolean range, Boolean touch, uint32_t options);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef, uint64_t, uint32_t index, uint32_t identity,
    uint32_t eventMask, double x, double y, double z, double pressure, double twist, Boolean range, Boolean touch,
    uint32_t options);
extern void IOHIDEventAppendEvent(IOHIDEventRef, IOHIDEventRef, uint32_t);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef, uint32_t field, long value);
extern void IOHIDEventSetSenderID(IOHIDEventRef, uint64_t);
extern IOHIDEventRef IOHIDEventCreateKeyboardEvent(CFAllocatorRef, uint64_t, uint32_t page, uint32_t usage,
    Boolean down, uint32_t options);
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);
extern CFTypeRef IOHIDServiceClientGetRegistryID(IOHIDServiceClientRef);
static uint64_t sender = 0x000000010000027FULL;
static uint64_t buttons;                /* the consumer-page (0x0C) service: the side buttons */

/* The display's own digitizer (usage page 0x0D): backboardd takes touches by their sender. */
static void
find_digitizer(void)
{
	CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
	CFIndex n = services ? CFArrayGetCount(services) : 0;
	int found = 0;
	for (CFIndex i = 0; i < n; i++) {
		IOHIDServiceClientRef s = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
		CFTypeRef page = IOHIDServiceClientCopyProperty(s, CFSTR("PrimaryUsagePage"));
		CFTypeRef usage = IOHIDServiceClientCopyProperty(s, CFSTR("PrimaryUsage"));
		int pg = 0, us = 0;
		if (page && CFGetTypeID(page) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)page, kCFNumberIntType, &pg);
		if (usage && CFGetTypeID(usage) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)usage, kCFNumberIntType, &us);
		CFTypeRef rid = IOHIDServiceClientGetRegistryID(s);
		uint64_t id = 0;
		if (rid && CFGetTypeID(rid) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)rid, kCFNumberSInt64Type, &id);
		dprintf(2, "hidtouch: service page %#x usage %#x id %#llx\n", pg, us, (unsigned long long)id);
		/* the lowest id: the panel's kernel service (a user-space virtual digitizer can be listed too) */
		if (pg == 0x0c && id != 0 && !buttons) {
			buttons = id;
		}
		if (pg == 0x0d && id != 0 && (!found || id < sender)) {
			sender = id;
			found = 1;
		}
		if (page) CFRelease(page);
		if (usage) CFRelease(usage);
	}
	dprintf(2, "hidtouch: %ld services; sender %#llx\n", (long)n, (unsigned long long)sender);
	if (services) CFRelease(services);
}

#define kTransducerHand         3
#define kEventRange             0x1
#define kEventTouch             0x2
#define kEventPosition          0x4
#define kEventFromEdgeTip       0x800    /* kIOHIDDigitizerEventFromEdgeTip: what makes home/edge gestures (0071) */
#define EDGE_PX                 48
static uint32_t edge;               /* the contact began at a panel edge: the bit for its whole life */
#define kFieldDisplayIntegrated ((11u << 16) | 25u)     /* kIOHIDEventFieldDigitizerIsDisplayIntegrated */
#define PANEL_W 1080.0
#define PANEL_H 2340.0


static void
send(double px, double py, uint32_t mask, int touching)
{
	mask |= edge;
	uint64_t now = mach_absolute_time();
	double x = px / PANEL_W, y = py / PANEL_H;         /* the digitizer speaks in 0..1 */
	IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, kTransducerHand, 0, 0, mask, 0,
	    x, y, 0, 0, 0, touching, touching, 0);
	IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(kCFAllocatorDefault, now, 1, 2, mask, x, y, 0,
	    touching ? 0.5 : 0, 0, touching, touching, 0);
	IOHIDEventSetIntegerValue(hand, kFieldDisplayIntegrated, 1);
	IOHIDEventSetIntegerValue(finger, kFieldDisplayIntegrated, 1);
	IOHIDEventAppendEvent(hand, finger, 0);
	IOHIDEventSetSenderID(hand, sender);
	IOHIDEventSystemClientDispatchEvent(client, hand);
	CFRelease(finger);
	CFRelease(hand);
}

static mach_timebase_info_data_t tb;
static uint64_t next_at, gap_max, gap_sum, gap_n, last_sent;

static uint64_t
us_to_abs(uint64_t us)
{
	return us * 1000ull * tb.denom / tb.numer;
}

/* the next move's deadline, STEP_US after the last deadline (not after whenever this woke) */
static void
step_wait(void)
{
	uint64_t now = mach_absolute_time();
	next_at = next_at == 0 || next_at + us_to_abs(STEP_US) < now ? now + us_to_abs(STEP_US) : next_at + us_to_abs(STEP_US);
	mach_wait_until(next_at);
	now = mach_absolute_time();
	if (last_sent != 0) {
		uint64_t gap = (now - last_sent) * tb.numer / tb.denom / 1000ull;
		gap_max = gap > gap_max ? gap : gap_max;
		gap_sum += gap;
		gap_n++;
	}
	last_sent = now;
}

static void
realtime(void)
{
	thread_time_constraint_policy_data_t p;
	mach_timebase_info(&tb);
	p.period = (uint32_t)us_to_abs(STEP_US);
	p.computation = (uint32_t)us_to_abs(500);
	p.constraint = (uint32_t)us_to_abs(STEP_US);
	p.preemptible = 1;
	kern_return_t kr = thread_policy_set(mach_thread_self(), THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&p,
	    THREAD_TIME_CONSTRAINT_POLICY_COUNT);
	dprintf(2, "hidtouch: time-constraint thread %s (%d)\n", kr == KERN_SUCCESS ? "on" : "NOT on", kr);
}

static void
swipe(double x1, double y1, double x2, double y2, int ms)
{
	int steps = ms * 1000 / STEP_US > 2 ? ms * 1000 / STEP_US : 2;
	edge = (x1 < EDGE_PX || x1 > PANEL_W - 1 - EDGE_PX || y1 < EDGE_PX || y1 > PANEL_H - 1 - EDGE_PX) ? kEventFromEdgeTip : 0;
	next_at = 0;
	last_sent = mach_absolute_time();
	send(x1, y1, kEventRange | kEventTouch, 1);
	for (int i = 1; i <= steps; i++) {
		step_wait();
		send(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, kEventPosition, 1);
	}
	usleep(16000);
	send(x2, y2, kEventRange | kEventTouch, 0);
	edge = 0;
}

static void
drag(char *args)
{
	double x, y, nx, ny; int ms, used = 0;
	if (sscanf(args, "%lf %lf%n", &x, &y, &used) != 2) {
		return;
	}
	args += used;
	edge = 0;
	next_at = 0;
	last_sent = mach_absolute_time();
	send(x, y, kEventRange | kEventTouch, 1);
	while (sscanf(args, "%lf %lf %d%n", &nx, &ny, &ms, &used) == 3) {
		args += used;
		int steps = ms * 1000 / STEP_US > 2 ? ms * 1000 / STEP_US : 2;
		for (int i = 1; i <= steps; i++) {
			step_wait();
			send(x + (nx - x) * i / steps, y + (ny - y) * i / steps, kEventPosition, 1);
		}
		x = nx; y = ny;
	}
	usleep(16000);
	send(x, y, kEventRange | kEventTouch, 0);
}

int
main(void)
{
	char buf[4096] = "";
	int fd = open("/tmp/touch_cmd", O_RDONLY);
	if (fd < 0) {
		return 1;
	}
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	unlink("/tmp/touch_cmd");
	if (n <= 0) {
		return 1;
	}
	buf[n] = 0;
	client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
	if (client == NULL) {
		dprintf(2, "hidtouch: no event system client\n");
		return 2;
	}
	find_digitizer();
	realtime();
	for (char *line = strtok(buf, "\n"); line != NULL; line = strtok(NULL, "\n")) {
		double a, b, c, d; int ms; unsigned pg, us;
		if (sscanf(line, "tap %lf %lf", &a, &b) == 2) {
			send(a, b, kEventRange | kEventTouch, 1);
			usleep(80000);
			send(a, b, kEventRange | kEventTouch, 0);
		} else if (sscanf(line, "swipe %lf %lf %lf %lf %d", &a, &b, &c, &d, &ms) == 5) {
			swipe(a, b, c, d, ms);
		} else if (strncmp(line, "drag ", 5) == 0) {
			drag(line + 5);
		} else if (sscanf(line, "key %x %x %d", &pg, &us, &ms) == 3) {
			/* "key 0c 30 120": a button pressed for 120 ms (0x0C/0x30 = the power/lock button),
			 * sent as the buttons service so backboardd takes it as the real one */
			for (int down = 1; down >= 0; down--) {
				IOHIDEventRef k = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(),
				    (uint32_t)pg, (uint32_t)us, down, 0);
				IOHIDEventSetSenderID(k, buttons ? buttons : sender);
				IOHIDEventSystemClientDispatchEvent(client, k);
				CFRelease(k);
				if (down) {
					usleep((useconds_t)ms * 1000);
				}
			}
		} else if (sscanf(line, "sleep %d", &ms) == 1) {
			usleep((useconds_t)ms * 1000);
		} else {
			continue;
		}
		dprintf(2, "hidtouch: %s\n", line);
		usleep(50000);
	}
	if (gap_n != 0) {
		dprintf(2, "hidtouch: %llu moves, %llu us apart on average, %llu at most (asked %d)\n", (unsigned long long)gap_n,
		    (unsigned long long)(gap_sum / gap_n), (unsigned long long)gap_max, STEP_US);
	}
	return 0;
}
