/* screencap: copy the panel (IOSurface 1, the kernel's AppleCLCD framebuffer) to /tmp/screen.raw.
 * (raphael copy, 2026-11-07: the scanned-out surface is one of backboardd's pool, which the GPU writes and
 * xnu 0131 no longer flushes per frame: the CPU read lines it had cached the last time this surface was
 * captured -- the screenshot was a frame or a state behind. They are dropped (sys_dcache_flush) first.)
 * File = 16-byte header (magic "SCAP", width, height, bytesPerRow; u32 LE each) + rows of BGRA.
 * Written to a temporary name and renamed, so a reader never sees half a file.
 * Host side: tools/screencap.py pulls it and makes a PNG. */
#include <IOSurface/IOSurfaceRef.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <libkern/OSCacheControl.h>

static int dump(uint32_t id, const char *path);

/* /tmp/screencap_ids (optional): surface ids to dump as /tmp/surf_<id>.raw; else the panel to /tmp/screen.raw */
int
main(void)
{
	char ids[256] = "";
	int fd = open("/tmp/screencap_ids", O_RDONLY);
	if (fd >= 0) {
		ssize_t n = read(fd, ids, sizeof(ids) - 1);
		close(fd);
		unlink("/tmp/screencap_ids");
		if (n > 0) {
			ids[n] = 0;
			for (char *p = ids; *p;) {
				char path[64];
				unsigned long id = strtoul(p, &p, 10);
				if (id == 0) { if (*p) { p++; } continue; }
				snprintf(path, sizeof(path), "/tmp/surf_%lu.raw", id);
				dump((uint32_t)id, path);
			}
			return 0;
		}
	}
	/* the surface the display engine scans out now (kernel 0170 kern.sweet_scanout_id; with the VIG0
	 * scaler it is one of backboardd's, not surface 1), else surface 1 as before */
	uint32_t live = 0;
	size_t n = sizeof(live);
	if (sysctlbyname("kern.sweet_scanout_id", &live, &n, NULL, 0) != 0 || live == 0) {
		live = 1;
	}
	return dump(live, "/tmp/screen.raw");
}

static int
dump(uint32_t id, const char *path)
{
	IOSurfaceRef s = IOSurfaceLookup(id);
	uint32_t hdr[4];
	int fd;
	char part[80];

	if (s == NULL) {
		dprintf(2, "screencap: no IOSurface %u\n", id);
		return 1;
	}
	IOSurfaceLock(s, kIOSurfaceLockReadOnly, NULL);
	const uint8_t *base = IOSurfaceGetBaseAddress(s);
	size_t w = IOSurfaceGetWidth(s), h = IOSurfaceGetHeight(s), bpr = IOSurfaceGetBytesPerRow(s);
	if (base != NULL && h != 0) {
		sys_dcache_flush((void *)base, h * bpr);        /* (clean lines only: nothing written back) */
	}
	if (base == NULL || w == 0 || h == 0 || bpr < w * 4) {
		dprintf(2, "screencap: surface %u has no pixels (base %p %zux%zu bpr %zu)\n", id, (void *)base, w, h, bpr);
		IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
		return 2;
	}
	snprintf(part, sizeof(part), "%s.part", path);
	fd = open(part, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) {
		dprintf(2, "screencap: cannot write %s\n", part);
		IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
		return 3;
	}
	memcpy(hdr, "SCAP", 4);
	hdr[1] = (uint32_t)w; hdr[2] = (uint32_t)h; hdr[3] = (uint32_t)(w * 4);
	write(fd, hdr, sizeof(hdr));
	static uint8_t row[4 * 4096];
	for (size_t y = 0; y < h; y++) {
		memcpy(row, base + y * bpr, w * 4);     /* one row at a time out of the (uncached) panel memory */
		write(fd, row, w * 4);
	}
	close(fd);
	IOSurfaceUnlock(s, kIOSurfaceLockReadOnly, NULL);
	rename(part, path);
	dprintf(2, "screencap: surface %u %zux%zu written to %s\n", id, w, h, path);
	return 0;
}
