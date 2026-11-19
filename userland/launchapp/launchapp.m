/* launchapp: open an app through FrontBoard's system service (the same route
 * SpringBoard uses), since LaunchServices is absent from this userland.
 *
 *   /tmp/launch_args = "<bundle-id>"            -> open that app
 *   /tmp/launch_args = "ENUM"                   -> list what FrontBoard knows
 *   raphael additions, more whitespace-separated words after the bundle id:
 *     out=PATH     the app's stdout and stderr to PATH (FrontBoard debug options, as Xcode does)
 *     env=K=V      an environment variable for the app (repeatable)
 *   and the device is asked to unlock (__UnlockDevice) and an old instance killed (__KillExisting).
 *
 * Log -> /tmp/launchapp.txt , every attempt reported.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static FILE *o;
static void p(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vfprintf(o, fmt, ap);
	va_end(ap);
	fflush(o);
}

typedef id (*msg_id)(id, SEL);
typedef id (*msg_id_id)(id, SEL, id);
typedef void (*msg_void_id)(id, SEL, id);

int main(void)
{
	o = fopen("/tmp/launchapp.txt", "w");
	if (!o) return 1;

	char bid[256] = {0};
	NSString *outPath = nil;
	NSMutableDictionary *env = [NSMutableDictionary dictionary];
	FILE *a = fopen("/tmp/launch_args", "r");
	if (a) {
		char w[512];
		if (fscanf(a, "%255s", bid) != 1) bid[0] = 0;
		while (fscanf(a, "%511s", w) == 1) {
			if (!strncmp(w, "out=", 4)) {
				outPath = [NSString stringWithUTF8String:w + 4];
			} else if (!strncmp(w, "env=", 4) && strchr(w + 4, '=')) {
				char *eq = strchr(w + 4, '=');
				*eq = 0;
				env[[NSString stringWithUTF8String:w + 4]] = [NSString stringWithUTF8String:eq + 1];
			}
		}
		fclose(a);
	}
	p("request: %s\n", bid[0] ? bid : "(empty)");

	void *fbs = dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
	p("dlopen FrontBoardServices: %s\n", fbs ? "ok" : dlerror());

	Class svc = (Class)objc_getClass("FBSOpenApplicationService");
	p("FBSOpenApplicationService: %s\n", svc ? "found" : "nil");
	Class sys = (Class)objc_getClass("FBSSystemService");
	p("FBSSystemService: %s\n", sys ? "found" : "nil");
	Class wsp = (Class)objc_getClass("LSApplicationWorkspace");
	p("LSApplicationWorkspace: %s\n", wsp ? "found" : "nil");

	if (!bid[0] || !strcmp(bid, "ENUM")) {
		/* FBSSystemService has +processesForLaunching / -systemApplicationBundleIdentifier
		 * but the pragmatic enumeration is FBSProcessManager; just report what's runnable. */
		if (sys) {
			id s = ((msg_id)objc_msgSend)((id)sys, sel_registerName("sharedService"));
			p("sharedService: %s\n", s ? "ok" : "nil");
		}
		fclose(o);
		return 0;
	}

	if (!svc) { p("cannot launch: no FBSOpenApplicationService\n"); fclose(o); return 1; }

	id service = nil;
	@try {
		service = ((msg_id)objc_msgSend)((id)svc, sel_registerName("serviceWithDefaultShellEndpoint"));
		p("serviceWithDefaultShellEndpoint: %s\n", service ? "ok" : "nil");
	} @catch (id e) {
		p("serviceWithDefaultShellEndpoint threw: %s\n", [[e description] UTF8String]);
	}
	if (!service) { p("no service\n"); fclose(o); return 1; }

	Class optc = (Class)objc_getClass("FBSOpenApplicationOptions");
	p("FBSOpenApplicationOptions: %s\n", optc ? "found" : "nil");
	id opts = nil;
	if (optc) {
		NSMutableDictionary *d = [NSMutableDictionary dictionary];
		NSMutableDictionary *dbg = [NSMutableDictionary dictionary];
		d[@"__UnlockDevice"] = @YES;
		if (outPath) {
			dbg[@"__StdOutPath"] = outPath;
			dbg[@"__StdErrPath"] = outPath;
		}
		if ([env count]) {
			dbg[@"__Environment"] = env;
		}
		if ([dbg count]) {
			dbg[@"__KillExisting"] = @YES;
			d[@"__DebugOptions"] = dbg;
		}
		p("options: %s\n", [[d description] UTF8String]);
		opts = ((id (*)(id, SEL, id))objc_msgSend)((id)optc,
		    sel_registerName("optionsWithDictionary:"), d);
		p("options: %s\n", opts ? "ok" : "nil");
	}

	SEL openApp = sel_registerName("openApplication:withOptions:completion:");
	if (![service respondsToSelector:openApp]) {
		p("no openApplication:withOptions:completion:\n");
	}
	@try {
		((void (*)(id, SEL, id, id, id))objc_msgSend)(service, openApp,
		    [NSString stringWithUTF8String:bid], opts,
		    ^(id params, id error) {
			p("completion params=%s error=%s\n",
			    params ? [[params description] UTF8String] : "nil",
			    error ? [[error description] UTF8String] : "nil");
		});
		p("openApplication: sent\n");
	} @catch (id e) {
		p("openApplication threw: %s\n", [[e description] UTF8String]);
	}

	/* give the completion handler a chance to fire */
	for (int i = 0; i < 40; i++) {
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	}
	p("done\n");
	fclose(o);
	return 0;
}