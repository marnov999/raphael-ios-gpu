/* kvsshim.dylib: NSUbiquitousKeyValueStore kept in the app's own NSUserDefaults (keys prefixed "kvs."),
 * which is what an iPhone without iCloud gives an app -- a store that holds what was set. On this port the
 * real store holds nothing even within one process (userland/kvstest), and Monument Valley asserts that a
 * value it set reads back (SharedStorage_SetInt, check == _value). Loaded into the app by an
 * LC_LOAD_WEAK_DYLIB (tools/insert-dylib.py). */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *K(NSString *k) { return [@"kvs." stringByAppendingString:k ?: @""]; }
static NSUserDefaults *D(void) { return [NSUserDefaults standardUserDefaults]; }

@implementation NSUbiquitousKeyValueStore (SweetLocal)
- (id)sw_objectForKey:(NSString *)k { return [D() objectForKey:K(k)]; }
- (void)sw_setObject:(id)o forKey:(NSString *)k { if (o) [D() setObject:o forKey:K(k)]; else [D() removeObjectForKey:K(k)]; }
- (void)sw_removeObjectForKey:(NSString *)k { [D() removeObjectForKey:K(k)]; }
- (NSString *)sw_stringForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSString class]] ? o : nil; }
- (NSArray *)sw_arrayForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSArray class]] ? o : nil; }
- (NSDictionary *)sw_dictionaryForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSDictionary class]] ? o : nil; }
- (NSData *)sw_dataForKey:(NSString *)k { id o = [self objectForKey:k]; return [o isKindOfClass:[NSData class]] ? o : nil; }
- (long long)sw_longLongForKey:(NSString *)k { id o = [self objectForKey:k]; return [o respondsToSelector:@selector(longLongValue)] ? [o longLongValue] : 0; }
- (double)sw_doubleForKey:(NSString *)k { id o = [self objectForKey:k]; return [o respondsToSelector:@selector(doubleValue)] ? [o doubleValue] : 0; }
- (BOOL)sw_boolForKey:(NSString *)k { id o = [self objectForKey:k]; return [o respondsToSelector:@selector(boolValue)] ? [o boolValue] : NO; }
- (void)sw_setString:(NSString *)v forKey:(NSString *)k { [self setObject:v forKey:k]; }
- (void)sw_setArray:(NSArray *)v forKey:(NSString *)k { [self setObject:v forKey:k]; }
- (void)sw_setDictionary:(NSDictionary *)v forKey:(NSString *)k { [self setObject:v forKey:k]; }
- (void)sw_setData:(NSData *)v forKey:(NSString *)k { [self setObject:v forKey:k]; }
- (void)sw_setLongLong:(long long)v forKey:(NSString *)k { [self setObject:@(v) forKey:k]; }
- (void)sw_setDouble:(double)v forKey:(NSString *)k { [self setObject:@(v) forKey:k]; }
- (void)sw_setBool:(BOOL)v forKey:(NSString *)k { [self setObject:@(v) forKey:k]; }
- (NSDictionary *)sw_dictionaryRepresentation
{
	NSMutableDictionary *r = [NSMutableDictionary dictionary];
	[[D() dictionaryRepresentation] enumerateKeysAndObjectsUsingBlock:^(NSString *k, id o, BOOL *stop) {
		if ([k hasPrefix:@"kvs."]) r[[k substringFromIndex:4]] = o;
	}];
	return r;
}
- (BOOL)sw_synchronize { return YES; }
@end

__attribute__((constructor)) static void init(void)
{
	Class c = [NSUbiquitousKeyValueStore class];
	const char *names[] = { "objectForKey:", "setObject:forKey:", "removeObjectForKey:", "stringForKey:",
		"arrayForKey:", "dictionaryForKey:", "dataForKey:", "longLongForKey:", "doubleForKey:", "boolForKey:",
		"setString:forKey:", "setArray:forKey:", "setDictionary:forKey:", "setData:forKey:",
		"setLongLong:forKey:", "setDouble:forKey:", "setBool:forKey:", "dictionaryRepresentation", "synchronize" };
	for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
		char sw[96];
		snprintf(sw, sizeof(sw), "sw_%s", names[i]);
		Method a = class_getInstanceMethod(c, sel_registerName(names[i]));
		Method b = class_getInstanceMethod(c, sel_registerName(sw));
		if (a && b)
			method_exchangeImplementations(a, b);
	}
}
