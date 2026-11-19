/* keytest: does the keychain work? SecItemAdd / CopyMatching / Delete of a generic password, the
 * OSStatus of each, for several kSecAttrAccessible classes (Minecraft: "Couldn't add the Keychain Item."). */
#import <Foundation/Foundation.h>
#import <Security/Security.h>

int main(void)
{
	@autoreleasepool {
		CFTypeRef classes[] = { NULL, kSecAttrAccessibleAfterFirstUnlock, kSecAttrAccessibleWhenUnlocked,
		    kSecAttrAccessibleAlways, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly };
		const char *names[] = { "default", "AfterFirstUnlock", "WhenUnlocked", "Always", "AfterFirstUnlockThisDeviceOnly" };
		for (unsigned i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
			NSString *acct = [NSString stringWithFormat:@"keytest-%u", i];
			NSDictionary *q = @{ (id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: @"keytest",
			    (id)kSecAttrAccount: acct };
			SecItemDelete((CFDictionaryRef)q);
			NSMutableDictionary *add = [q mutableCopy];
			add[(id)kSecValueData] = [@"secret" dataUsingEncoding:NSUTF8StringEncoding];
			if (classes[i] != NULL) {
				add[(id)kSecAttrAccessible] = (__bridge id)classes[i];
			}
			OSStatus a = SecItemAdd((CFDictionaryRef)add, NULL);
			NSMutableDictionary *get = [q mutableCopy];
			get[(id)kSecReturnData] = @YES;
			CFTypeRef out = NULL;
			OSStatus g = SecItemCopyMatching((CFDictionaryRef)get, &out);
			OSStatus d = SecItemDelete((CFDictionaryRef)q);
			printf("%-32s add %d get %d (%s) delete %d\n", names[i], (int)a, (int)g,
			    out ? "data back" : "nothing", (int)d);
			if (out) CFRelease(out);
		}
	}
	return 0;
}
