/* surfuse: /tmp/surfuse_args = "<first id> <last id>" -> /tmp/surfuse.txt: for each IOSurface id that exists, its
 * size, IOSurfaceIsInUse, use count and seed -- why CoreAnimation does not take its display surfaces again. */
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <IOSurface/IOSurfaceRef.h>


int
main(void)
{
	unsigned first = 1, last = 64;
	FILE *a = fopen("/tmp/surfuse_args", "r");
	if (a != NULL) {
		if (fscanf(a, "%u %u", &first, &last) != 2) {
			first = 1;
			last = 64;
		}
		fclose(a);
	}
	FILE *o = fopen("/tmp/surfuse.part", "w");
	if (o == NULL) {
		return 1;
	}
	for (unsigned id = first; id <= last; id++) {
		IOSurfaceRef s = IOSurfaceLookup(id);
		if (s == NULL) {
			continue;
		}
		fprintf(o, "%u %zux%zu bpr %zu in-use %d use-count %d seed %u\n", id, IOSurfaceGetWidth(s), IOSurfaceGetHeight(s),
		    IOSurfaceGetBytesPerRow(s), IOSurfaceIsInUse(s), IOSurfaceGetUseCount(s), IOSurfaceGetSeed(s));
		CFRelease(s);
	}
	fclose(o);
	rename("/tmp/surfuse.part", "/tmp/surfuse.txt");
	return 0;
}
