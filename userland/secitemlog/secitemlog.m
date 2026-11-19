/* secitemlog.dylib: DYLD_INSERT_LIBRARIES interposer that logs every SecItem call (query, status) of an
 * app to /tmp/secitem-<name>.log -- what a keychain-using game asked for and what the keychain answered. */
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stdio.h>
#include <unistd.h>

static FILE *lf;
static void logq(const char *what, CFDictionaryRef q, OSStatus st)
{
	if (lf == NULL) {
		char p[256];
		snprintf(p, sizeof(p), "/tmp/secitem-%s.log", getprogname());
		lf = fopen(p, "a");
		if (lf == NULL) return;
	}
	NSMutableDictionary *d = [(__bridge NSDictionary *)q mutableCopy];
	if (d[(id)kSecValueData]) d[(id)kSecValueData] = [NSString stringWithFormat:@"<%lu bytes>", (unsigned long)[d[(id)kSecValueData] length]];
	fprintf(lf, "%s -> %d  %s\n", what, (int)st, [[[d description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] UTF8String]);
	fflush(lf);
}
static OSStatus my_add(CFDictionaryRef a, CFTypeRef *r) { OSStatus s = SecItemAdd(a, r); logq("SecItemAdd", a, s); return s; }
static OSStatus my_copy(CFDictionaryRef q, CFTypeRef *r) { OSStatus s = SecItemCopyMatching(q, r); logq("SecItemCopyMatching", q, s); return s; }
static OSStatus my_update(CFDictionaryRef q, CFDictionaryRef u) { OSStatus s = SecItemUpdate(q, u); logq("SecItemUpdate", q, s); logq("  (update attrs)", u, s); return s; }
static OSStatus my_delete(CFDictionaryRef q) { OSStatus s = SecItemDelete(q); logq("SecItemDelete", q, s); return s; }

__attribute__((used)) static struct { const void *n, *o; } interposers[] __attribute__((section("__DATA,__interpose"))) = {
	{ (const void *)my_add, (const void *)SecItemAdd },
	{ (const void *)my_copy, (const void *)SecItemCopyMatching },
	{ (const void *)my_update, (const void *)SecItemUpdate },
	{ (const void *)my_delete, (const void *)SecItemDelete },
};
