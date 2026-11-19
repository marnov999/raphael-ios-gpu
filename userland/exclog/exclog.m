/* exclog.dylib (DYLD_INSERT_LIBRARIES): writes every Objective-C exception an app throws -- name and
 * reason -- to /tmp/exc-<name>.log. Through objc_setExceptionPreprocessor, which the runtime runs on
 * every throw: interposing objc_exception_throw misses the throws inside the dyld shared cache, whose
 * calls between libraries are bound directly. Crash reports keep the backtrace, not the reason. */
#import <Foundation/Foundation.h>
#include <objc/objc-exception.h>
#include <stdio.h>
#include <unistd.h>

static objc_exception_preprocessor previous;

static id logit(id e)
{
	char p[256];
	snprintf(p, sizeof(p), "/tmp/exc-%s.log", getprogname());
	FILE *f = fopen(p, "a");
	if (f != NULL) {
		@try {
			fprintf(f, "%s: %s\n", [[e name] UTF8String] ?: "?", [[e reason] UTF8String] ?: "?");
		} @catch (id x) { }
		fclose(f);
	}
	return previous ? previous(e) : e;
}

__attribute__((constructor)) static void init(void)
{
	previous = objc_setExceptionPreprocessor(logit);
}
