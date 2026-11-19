/* kvstest: does NSUbiquitousKeyValueStore keep a value in this process (Monument Valley asserts it
 * does: SharedStorage_SetInt, check == _value)? */
#import <Foundation/Foundation.h>
int main(void)
{
	@autoreleasepool {
		NSUbiquitousKeyValueStore *s = [NSUbiquitousKeyValueStore defaultStore];
		printf("store %p\n", s);
		[s setLongLong:42 forKey:@"kvstest"];
		printf("after set: %lld\n", [s longLongForKey:@"kvstest"]);
		BOOL ok = [s synchronize];
		printf("synchronize %d, after sync: %lld\n", ok, [s longLongForKey:@"kvstest"]);
		[s setObject:@"hello" forKey:@"kvstest2"];
		printf("string: %s\n", [[s stringForKey:@"kvstest2"] UTF8String] ?: "(nil)");
	}
	return 0;
}
