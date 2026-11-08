/*
 * mdss: the display block from userland, through kern.sweet_mdss (xnu 0128, bsd/dev/sweet_panel.c).
 * Offsets are from MDSS 0x0ae00000 (absolute 0x0aeXXXXX / 0x0afXXXXX taken as well), in hex.
 *
 *   mdss r OFF [N]               N words from OFF
 *   mdss w OFF VAL [OFF VAL..]   write, read back ("sleep MS" pairs wait between them; also comma-joined)
 *   mdss dcs B B .. [, B B ..]   DCS long writes to the panel, one packet per comma-separated group
 *   mdss te [SECS]               the panel's TEs for SECS (3): rate, period min/mean/max
 *   mdss touch 0|1               the touchscreen's own touches off (kern.sweet_touch_mute) / on
 *   mdss top [SECS]              the processes that used the most CPU over SECS (% of one core)
 *   mdss kill NAME               SIGKILL to the processes of that name
 *   mdss key N                   a button pressed and let go (0 power, 1 volume up, 2 volume down)
 *   mdss sysctlw NAME VALUE      a 32-bit sysctl set
 *   mdss sysctl NAME [N [MS]]    a 32-bit sysctl, N times MS apart
 *   mdss sysctls NAME..          string sysctls (kern.sweet_dvfs_stats, kern.sweet_power, kern.sweet_temps)
 *   mdss line [MS]               the tear check's read pointer every 0.1 ms for MS (20): line, us
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <signal.h>
int proc_listallpids(void *buffer, int buffersize);       /* (libproc, not in this SDK) */
int proc_name(int pid, void *buffer, uint32_t buffersize);
int proc_pid_rusage(int pid, int flavor, rusage_info_t *buffer);
#include <sys/resource.h>
#include <mach/mach_time.h>

struct req {
	uint32_t op, off, val, n;
	uint8_t  bytes[56];
};
struct out {
	uint32_t val, ok;
	uint64_t at;
	uint32_t count, pad;
};

static int
call(struct req *rq, struct out *o)
{
	size_t len = sizeof(*o);
	memset(o, 0, sizeof(*o));
	if (sysctlbyname("kern.sweet_mdss", o, &len, rq, sizeof(*rq)) != 0) {
		perror("kern.sweet_mdss");
		return -1;
	}
	return 0;
}

static uint32_t
off_of(const char *s)
{
	uint32_t v = (uint32_t)strtoul(s, NULL, 16);
	return v >= 0x0ae00000u ? v - 0x0ae00000u : v;
}

static double
us_of(uint64_t abs)
{
	static mach_timebase_info_data_t tb;
	if (tb.denom == 0) {
		mach_timebase_info(&tb);
	}
	return (double)abs * tb.numer / tb.denom / 1000.0;
}

/*
 * The TEs: the tear check's TE count (INT_COUNT_VAL [31:16]) stays 0 here, so a TE is where its read
 * pointer line drops back (to VSYNC_INIT_VAL); its time is the kernel's estimate (op 3: now less the
 * lines since it), taken at the first sample after the drop.
 */
static int
te(double secs)
{
	struct req rq = { .op = 3 };
	struct req rl = { .op = 0, .off = 0x6b800u + 0x298u };
	struct out o, l;
	uint64_t t0 = mach_absolute_time(), first_at = 0, last_at = 0;
	uint32_t prev_line = 0, n = 0, maxline = 0;
	double mn = 1e9, mx = 0;
	for (;;) {
		if (call(&rl, &l) != 0 || call(&rq, &o) != 0) {
			return 1;
		}
		uint32_t line = l.val & 0xffffu;
		maxline = line > maxline ? line : maxline;
		if (o.ok && prev_line != 0 && line < prev_line) {
			if (first_at == 0) {
				first_at = o.at;
			} else {
				double p = us_of(o.at - last_at);
				mn = p < mn ? p : mn;
				mx = p > mx ? p : mx;
				n++;
			}
			last_at = o.at;
		}
		prev_line = line;
		if (us_of(mach_absolute_time() - t0) >= secs * 1e6) {
			break;
		}
		usleep(200);
	}
	if (n == 0) {
		printf("te: no TE in %.1f s (line max %u)\n", secs, maxline);
		return 1;
	}
	double mean = us_of(last_at - first_at) / n;
	printf("te: %u TEs, %.3f Hz, period mean %.1f us, min %.1f, max %.1f; line max %u\n", n, 1e6 / mean, mean, mn, mx,
	    maxline);
	return 0;
}

static int
line(double ms)
{
	struct req rq = { .op = 0, .off = 0x6b800u + 0x298u };
	struct out o;
	uint64_t t0 = mach_absolute_time();
	for (;;) {
		if (call(&rq, &o) != 0) {
			return 1;
		}
		double us = us_of(mach_absolute_time() - t0);
		struct req rw = { .op = 0, .off = 0x6b800u + 0x2b0u };      /* LINE_COUNT: the write pointer */
		struct out w;
		if (call(&rw, &w) != 0) {
			return 1;
		}
		printf("%8.1f us  te %5u  line %5u  wr %5u\n", us, o.val >> 16, o.val & 0xffffu, w.val & 0xffffu);
		if (us >= ms * 1000.0) {
			break;
		}
		usleep(100);
	}
	return 0;
}

int
main(int argc, char **argv)
{
	struct req rq;
	struct out o;
	setvbuf(stdout, NULL, _IONBF, 0);
	if (argc < 2) {
		fprintf(stderr, "usage: mdss r OFF [N] | w OFF VAL.. | dcs B.. [, B..] | te [SECS] | line [MS]\n");
		return 2;
	}
	if (strcmp(argv[1], "r") == 0 && argc >= 3) {
		uint32_t off = off_of(argv[2]), n = argc >= 4 ? (uint32_t)strtoul(argv[3], NULL, 0) : 1;
		for (uint32_t i = 0; i < n; i++) {
			memset(&rq, 0, sizeof(rq));
			rq.op = 0;
			rq.off = off + 4 * i;
			if (call(&rq, &o) != 0) {
				return 1;
			}
			if (i % 8 == 0) {
				printf("%05x:", off + 4 * i);
			}
			printf(" %08x%s", o.val, i % 8 == 7 || i + 1 == n ? "\n" : "");
		}
		return 0;
	}
	if (strcmp(argv[1], "w") == 0) {
		/* the pairs as arguments, or comma-joined (runlog passes ~14 arguments at most) */
		static char *tok[512];
		int nt = 0;
		for (int i = 2; i < argc; i++) {
			for (char *p = argv[i], *t; (t = strsep(&p, ",")) != NULL && nt < 512;) {
				if (*t != '\0') {
					tok[nt++] = t;
				}
			}
		}
		for (int i = 0; i + 1 < nt; i += 2) {
			if (strcmp(tok[i], "sleep") == 0) {         /* "sleep MS" between writes */
				usleep((useconds_t)atoi(tok[i + 1]) * 1000);
				continue;
			}
			memset(&rq, 0, sizeof(rq));
			rq.op = 1;
			rq.off = off_of(tok[i]);
			rq.val = (uint32_t)strtoul(tok[i + 1], NULL, 16);
			if (call(&rq, &o) != 0) {
				return 1;
			}
			printf("%#x <- %08x: %08x\n", rq.off, rq.val, o.val);
		}
		return 0;
	}
	if (strcmp(argv[1], "dcs") == 0) {
		int i = 2;
		while (i < argc) {
			memset(&rq, 0, sizeof(rq));
			rq.op = 2;
			while (i < argc && strcmp(argv[i], ",") != 0 && rq.n < sizeof(rq.bytes)) {
				rq.bytes[rq.n++] = (uint8_t)strtoul(argv[i++], NULL, 16);
			}
			i++;
			if (rq.n == 0) {
				continue;
			}
			if (call(&rq, &o) != 0) {
				return 1;
			}
			printf("dcs");
			for (uint32_t k = 0; k < rq.n; k++) {
				printf(" %02x", rq.bytes[k]);
			}
			printf(": %s\n", o.ok ? "sent" : "NOT sent");
		}
		return 0;
	}
	if (strcmp(argv[1], "touch") == 0 && argc >= 3) {      /* touch 0: the touchscreen muted, 1: on */
		int mute = atoi(argv[2]) == 0;
		if (sysctlbyname("kern.sweet_touch_mute", NULL, NULL, &mute, sizeof(mute)) != 0) {
			perror("kern.sweet_touch_mute");
			return 1;
		}
		printf("touchscreen %s\n", mute ? "muted (injected touches only)" : "on");
		return 0;
	}
	if (strcmp(argv[1], "top") == 0) {                     /* top [SECS]: the processes that used the most CPU over SECS (3) */
		double secs = argc >= 3 ? atof(argv[2]) : 3.0;
		static struct { int pid; uint64_t t0; char name[32]; } p[2048];
		int n = 0, pids[2048];
		int got = proc_listallpids(pids, sizeof(pids));
		for (int i = 0; i < got && n < 2048; i++) {
			struct rusage_info_v0 ri;
			if (proc_pid_rusage(pids[i], RUSAGE_INFO_V0, (rusage_info_t *)&ri) == 0) {
				p[n].pid = pids[i];
				p[n].t0 = ri.ri_user_time + ri.ri_system_time;
				proc_name(pids[i], p[n].name, sizeof(p[n].name));
				n++;
			}
		}
		usleep((useconds_t)(secs * 1e6));
		struct { double pct; int i; } top[2048];
		int m = 0;
		mach_timebase_info_data_t tb;
		mach_timebase_info(&tb);
		for (int i = 0; i < n; i++) {
			struct rusage_info_v0 ri;
			if (proc_pid_rusage(p[i].pid, RUSAGE_INFO_V0, (rusage_info_t *)&ri) == 0) {
				uint64_t d = ri.ri_user_time + ri.ri_system_time - p[i].t0;      /* (mach time units) */
				top[m].pct = (double)d * tb.numer / tb.denom / 1e9 / secs * 100.0;
				top[m].i = i;
				m++;
			}
		}
		for (int a = 0; a < m; a++) {
			for (int b = a + 1; b < m; b++) {
				if (top[b].pct > top[a].pct) {
					__typeof__(top[0]) t = top[a];
					top[a] = top[b];
					top[b] = t;
				}
			}
		}
		for (int a = 0; a < m && a < 12; a++) {
			printf("%6.1f%%  %5d %s\n", top[a].pct, p[top[a].i].pid, p[top[a].i].name);
		}
		return 0;
	}
	if (strcmp(argv[1], "kill") == 0 && argc >= 3) {       /* kill NAME: SIGKILL to every process of that name */
		int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
		size_t len = 0;
		if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0) {
			perror("kern.proc");
			return 1;
		}
		len += len / 4;
		struct kinfo_proc *kp = malloc(len);
		if (kp == NULL || sysctl(mib, 3, kp, &len, NULL, 0) != 0) {
			perror("kern.proc");
			return 1;
		}
		int killed = 0;
		for (size_t i = 0; i < len / sizeof(*kp); i++) {
			if (strcmp(kp[i].kp_proc.p_comm, argv[2]) == 0) {
				printf("kill %s pid %d: %d\n", argv[2], kp[i].kp_proc.p_pid, kill(kp[i].kp_proc.p_pid, SIGKILL));
				killed++;
			}
		}
		printf("%d killed\n", killed);
		return 0;
	}
	if (strcmp(argv[1], "key") == 0 && argc >= 3) {        /* key N: a button pressed (0 power, 1 volume up, 2 down) */
		int key = atoi(argv[2]);
		if (sysctlbyname("kern.sweet_key", NULL, NULL, &key, sizeof(key)) != 0) {
			perror("kern.sweet_key");
			return 1;
		}
		printf("key %d pressed\n", key);
		return 0;
	}
	if (strcmp(argv[1], "sysctlw") == 0 && argc >= 4) {    /* sysctlw NAME VALUE: a 32-bit sysctl set */
		uint32_t v = (uint32_t)strtoul(argv[3], NULL, 0), old = 0;
		size_t len = sizeof(old);
		if (sysctlbyname(argv[2], &old, &len, &v, sizeof(v)) != 0) {
			perror(argv[2]);
			return 1;
		}
		printf("%s: %u -> %u\n", argv[2], old, v);
		return 0;
	}
	if (strcmp(argv[1], "sysctls") == 0 && argc >= 3) {   /* sysctls NAME..: string sysctls, one line each */
		for (int i = 2; i < argc; i++) {
			char s[1024];
			size_t len = sizeof(s) - 1;
			memset(s, 0, sizeof(s));
			if (sysctlbyname(argv[i], s, &len, NULL, 0) != 0) {
				perror(argv[i]);
				return 1;
			}
			printf("%s: %s\n", argv[i], s);
		}
		return 0;
	}
	if (strcmp(argv[1], "sysctl") == 0 && argc >= 3) {    /* sysctl NAME [COUNT [MS]]: a 32-bit sysctl, COUNT times MS apart */
		int count = argc >= 4 ? atoi(argv[3]) : 1, ms = argc >= 5 ? atoi(argv[4]) : 10;
		for (int i = 0; i < count; i++) {
			uint32_t v = 0;
			size_t len = sizeof(v);
			if (sysctlbyname(argv[2], &v, &len, NULL, 0) != 0) {
				perror(argv[2]);
				return 1;
			}
			printf("%u%s", v, i + 1 == count ? "\n" : " ");
			usleep((useconds_t)ms * 1000);
		}
		return 0;
	}
	if (strcmp(argv[1], "te") == 0) {
		return te(argc >= 3 ? atof(argv[2]) : 3.0);
	}
	if (strcmp(argv[1], "line") == 0) {
		return line(argc >= 3 ? atof(argv[2]) : 20.0);
	}
	fprintf(stderr, "mdss: unknown command %s\n", argv[1]);
	return 2;
}
