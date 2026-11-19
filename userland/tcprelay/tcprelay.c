/* tcprelay: forward 0.0.0.0:LISTEN to 127.0.0.1:TARGET on the phone, so a service bound to the phone's loopback
 * (Gameface's inspector) is reachable over the USB network. Args from /tmp/tcprelay_args "LISTEN TARGET" (runlog
 * style: pushed with an exec bit it runs itself). Forks per connection; runs until killed. */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void pump(int a, int b)
{
	struct pollfd p[2] = { { a, POLLIN, 0 }, { b, POLLIN, 0 } };
	char buf[65536];
	for (;;) {
		if (poll(p, 2, -1) <= 0) return;
		for (int i = 0; i < 2; i++) {
			if (p[i].revents & (POLLIN | POLLHUP)) {
				ssize_t n = read(p[i].fd, buf, sizeof(buf));
				if (n <= 0) return;
				if (write(p[1 - i].fd, buf, (size_t)n) != n) return;
			}
		}
	}
}

int main(void)
{
	int lport = 19444, tport = 9444;
	FILE *f = fopen("/tmp/tcprelay_args", "r");
	if (f) { if (fscanf(f, "%d %d", &lport, &tport) != 2) { lport = 19444; tport = 9444; } fclose(f); }
	signal(SIGCHLD, SIG_IGN);
	int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
	setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
	struct sockaddr_in a = { .sin_len = sizeof(a), .sin_family = AF_INET, .sin_port = htons((uint16_t)lport) };
	if (bind(ls, (struct sockaddr *)&a, sizeof(a)) != 0 || listen(ls, 4) != 0) { perror("tcprelay bind"); return 1; }
	for (;;) {
		int c = accept(ls, NULL, NULL);
		if (c < 0) continue;
		if (fork() == 0) {
			int t = socket(AF_INET, SOCK_STREAM, 0);
			struct sockaddr_in d = { .sin_len = sizeof(d), .sin_family = AF_INET, .sin_port = htons((uint16_t)tport) };
			inet_pton(AF_INET, "127.0.0.1", &d.sin_addr);
			if (connect(t, (struct sockaddr *)&d, sizeof(d)) == 0) pump(c, t);
			_exit(0);
		}
		close(c);
	}
}
