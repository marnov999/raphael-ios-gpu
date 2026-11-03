/* sweet_shim.c (raphael copy of davinci-ios/gpu/userland/metal/sweet_shim.c, 10-29) -- GENERIC re-exec shim: launchd spawns us as
 *   [/usr/local/lib/sweet_shim <real-binary> <orig args...>]
 * we set DYLD_INSERT_LIBRARIES=metalshim and execv the real binary. Same trick
 * as bbd_shim but target-agnostic (real path = argv[1]), so one shim injects the
 * Metal shim into ANY launchd job we point at it (SpringBoard, renderers, ...). */
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#define SHIM "/usr/local/lib/metalshim.dylib"
static void LOG(const char*s){ size_t n=strlen(s); int c=open("/dev/console",O_WRONLY); if(c>=0){(void)write(c,s,n);close(c);}
   int fd=socket(AF_INET,SOCK_DGRAM,0); if(fd>=0){ struct sockaddr_in a; memset(&a,0,sizeof a); a.sin_family=AF_INET; a.sin_port=htons(5141); a.sin_addr.s_addr=inet_addr("192.168.9.1"); if(connect(fd,(struct sockaddr*)&a,sizeof a)==0)(void)send(fd,s,n,0); close(fd);} }
int main(int argc,char**argv){
   if(argc<2){ LOG("[sweet_shim] no target\n"); return 1; }
   setenv("DYLD_INSERT_LIBRARIES",SHIM,1);
   char b[256]; snprintf(b,sizeof b,"[sweet_shim] inject %s -> %s\n",SHIM,argv[1]); LOG(b);
   /* SpringBoard's first start in a boot never shows the wallpaper (grey); a second one does -- until
    * 2026-10-29 a TCC privacy kill always gave it that second start. Until the cause is found: the first
    * SpringBoard of a boot is ended once, 25 s in, and launchd starts it again (off: gltest/no_sb_respring). */
   const char *bn = strrchr(argv[1], '/'); bn = bn ? bn + 1 : argv[1];
   if (strcmp(bn, "SpringBoard") == 0 && access("/usr/local/gltest/no_sb_respring", F_OK) != 0) {
      /* the boot by kern.bootsessionuuid: kern.boottime is the same every boot while the clock starts at
       * the epoch (raphael 2026-11-03: the marker matched and the second boot got no restart) */
      struct timeval bt = { 0, 0 }; size_t n = sizeof bt;
      char want[64] = "", have[64] = "";
      sysctlbyname("kern.boottime", &bt, &n, NULL, 0);
      n = sizeof want - 2;
      if (sysctlbyname("kern.bootsessionuuid", want, &n, NULL, 0) != 0 || want[0] == 0) {
         snprintf(want, sizeof want, "%ld", (long)bt.tv_sec);
      }
      strlcat(want, "\n", sizeof want);
      int fd = open("/private/var/tmp/sweet_sb_boot", O_RDONLY);
      if (fd >= 0) { (void)read(fd, have, sizeof have - 1); close(fd); }
      if (strcmp(want, have) != 0) {
         fd = open("/private/var/tmp/sweet_sb_boot", O_WRONLY | O_CREAT | O_TRUNC, 0644);
         int wrote = fd >= 0;
         if (fd >= 0) { (void)write(fd, want, strlen(want)); close(fd); }
         pid_t sb = getpid();
         pid_t ch = fork();
         /* raphael: 25 s (davinci's) is too early here -- the restarted SpringBoard and PosterBoard come up grey;
          * a restart a minute in shows the wallpaper. /usr/local/gltest/sb_respring_secs = other seconds. */
         int secs = 60;
         FILE *sf = fopen("/usr/local/gltest/sb_respring_secs", "r");
         if (sf != NULL) { if (fscanf(sf, "%d", &secs) != 1 || secs < 1 || secs > 600) secs = 60; fclose(sf); }
         snprintf(b, sizeof b, "[sweet_shim] first SpringBoard of boot %ld (marker %s): restart in %d s by pid %d\n",
                  (long)bt.tv_sec, wrote ? "written" : "NOT written", secs, (int)ch);
         if (ch != 0) LOG(b);
         if (ch == 0) {
            setsid();
            for (int i = 0; i < 64; i++) close(i);
            LOG("[sweet_shim] restart child waiting\n");
            sleep((unsigned)secs);
            LOG("[sweet_shim] SpringBoard's first start of this boot ended once (its wallpaper)\n");
            kill(sb, SIGKILL);
            _exit(0);
         }
      }
   }
   execv(argv[1],&argv[1]);   /* argv[1]=real binary, argv[2..]=its args */
   snprintf(b,sizeof b,"[sweet_shim] execv(%s) FAILED\n",argv[1]); LOG(b);
   return 127;
}
