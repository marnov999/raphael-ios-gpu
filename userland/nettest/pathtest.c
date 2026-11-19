/* pathtest: does NWPathMonitor ever say what the network is? An app that waits for its first update
 * before showing a screen waits for ever if the system never sends one. */
#include <Network/Network.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

int main(void)
{
	nw_path_monitor_t m = nw_path_monitor_create();
	nw_path_monitor_set_queue(m, dispatch_get_main_queue());
	__block int n = 0;
	nw_path_monitor_set_update_handler(m, ^(nw_path_t p) {
		nw_path_status_t s = nw_path_get_status(p);
		printf("update %d: status %d (1 satisfied, 2 unsatisfied, 3 satisfiable)\n", ++n, (int)s);
		fflush(stdout);
	});
	nw_path_monitor_start(m);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		printf("after 10 s: %d update(s)\n", n);
		exit(0);
	});
	dispatch_main();
}
