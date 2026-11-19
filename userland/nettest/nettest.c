/* nettest: how this iOS fails offline -- a DNS lookup and a TCP connect to a public address, each timed.
 * A phone with no route fails at once (ENETUNREACH); one whose packets leave and never come back waits. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }

int main(void)
{
	double t0 = now();
	struct addrinfo *ai = NULL, hint = { .ai_socktype = SOCK_STREAM };
	int r = getaddrinfo("www.minecraft.net", "443", &hint, &ai);
	printf("getaddrinfo: %d (%s) after %.2f s\n", r, r ? gai_strerror(r) : "ok", now() - t0);
	if (ai) freeaddrinfo(ai);
	int s = socket(AF_INET, SOCK_STREAM, 0);
	fcntl(s, F_SETFL, O_NONBLOCK);
	struct sockaddr_in a = { .sin_len = sizeof(a), .sin_family = AF_INET, .sin_port = htons(443) };
	inet_pton(AF_INET, "1.1.1.1", &a.sin_addr);
	t0 = now();
	r = connect(s, (struct sockaddr *)&a, sizeof(a));
	int e = errno;
	printf("connect 1.1.1.1:443: %d errno %d (%s) after %.3f s\n", r, r ? e : 0, r ? strerror(e) : "ok", now() - t0);
	if (r != 0 && e == EINPROGRESS) {
		struct pollfd p = { s, POLLOUT, 0 };
		int n = poll(&p, 1, 8000);
		int err = 0; socklen_t l = sizeof(err);
		getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &l);
		printf("  poll %d revents %x so_error %d (%s) after %.2f s\n", n, p.revents, err, strerror(err), now() - t0);
	}
	close(s);
	return 0;
}
