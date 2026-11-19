/* stdio2file.dylib (DYLD_INSERT_LIBRARIES): the app's stdout and stderr to /tmp/out-<name>.log from its
 * first instruction. With CFLOG_FORCE_STDERR=1 in its environment NSLog goes there too, which is where
 * Unity's Debug.Log and its asserts end up. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

__attribute__((constructor)) static void init(void)
{
	char p[256];
	snprintf(p, sizeof(p), "/tmp/out-%s.log", getprogname());
	int fd = open(p, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd < 0)
		return;
	dup2(fd, 1);
	dup2(fd, 2);
	close(fd);
	setvbuf(stdout, NULL, _IOLBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);
}
