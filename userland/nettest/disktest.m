/* disktest: does asking iOS for free storage return (CacheDelete-backed keys can block if deleted is absent)? */
#import <Foundation/Foundation.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(void)
{
	@autoreleasepool {
		NSURL *u = [NSURL fileURLWithPath:NSHomeDirectory()];
		NSArray *keys = @[ NSURLVolumeAvailableCapacityKey, NSURLVolumeTotalCapacityKey,
			NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeAvailableCapacityForOpportunisticUsageKey ];
		for (NSURLResourceKey k in keys) {
			double t0 = now();
			NSError *e = nil;
			NSDictionary *d = [u resourceValuesForKeys:@[ k ] error:&e];
			printf("%-55s %s (%.2f s)%s\n", [k UTF8String], [[d[k] description] UTF8String] ?: "nil", now() - t0,
			    e ? [[e localizedDescription] UTF8String] : "");
			fflush(stdout);
		}
		double t0 = now();
		NSDictionary *a = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
		printf("attributesOfFileSystem free %s (%.2f s)\n", [[a[NSFileSystemFreeSize] description] UTF8String] ?: "nil", now() - t0);
	}
	return 0;
}
