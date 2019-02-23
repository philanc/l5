// const values

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <linux/limits.h>	// PATH_MAX
#include <sys/stat.h>	// stat
#include <sys/types.h>	// getpid
#include <unistd.h>	// getpid, stat
#include <dirent.h>	// dir...
#include <termios.h>	// termios
#include <sys/ioctl.h>	// TCGETS
#include <poll.h>	// poll


#define dispint(x)	printf(#x "= %d\n", x);
#define dispintx(x)	printf(#x "= 0x%08x\n", x);
#define dispsize(x)	printf("sizeof " #x "= %d\n", sizeof(x));

void main() {
	printf("---\n");
	dispint(PATH_MAX)
	dispsize(off_t)
	dispsize(uid_t)
	dispsize(mode_t)
	dispsize(nlink_t)
	dispsize(ino_t)
	dispsize(dev_t)
	dispsize(blksize_t)
	dispsize(blkcnt_t)
	dispsize(__time_t)
	dispsize(struct dirent)
	dispsize(struct stat)
	dispsize(struct timespec)
	dispsize(struct termios)
	dispintx(~(BRKINT | ICRNL | INPCK | ISTRIP | IXON))
	dispintx(~(OPOST))
	dispintx(CS8)
	dispintx(~(ECHO | ICANON | IEXTEN | ISIG))
	dispint(VMIN)
	dispint(VTIME)
	dispint(TCSAFLUSH)
	struct termios tos;
	dispint((char*)&(tos.c_line) - (char*)&tos)
	dispint((char*)&(tos.c_cc) - (char*)&tos)
	dispint((char*)&(tos.c_cc[VTIME]) - (char*)&tos)
	
	///f/p3/git/tmp/musl-1.1.18/include/bits/ioctl.h
	dispintx(TCGETS) // 0x5401 
	dispintx(TCSETS) // 0x5402	

	dispsize(struct pollfd)

	dispint((1,22,333))
	
	printf("---\n");
}


#ifdef ZZQQ


--- NOTES

--from bits/termios.h

typedef unsigned char   cc_t;
typedef unsigned int    speed_t;
typedef unsigned int    tcflag_t;

#define NCCS 32
struct termios
  {			size in bytes
    tcflag_t c_iflag;   4        /* input mode flags */
    tcflag_t c_oflag;   4       /* output mode flags */
    tcflag_t c_cflag;   4        /* control mode flags */
    tcflag_t c_lflag;   4        /* local mode flags */
    cc_t c_line;        1                /* line discipline */
    cc_t c_cc[NCCS];    32        /* control characters */
    speed_t c_ispeed;   4        /* input speed */
    speed_t c_ospeed;   4        /* output speed */
  };		total size = 57
		sizeof struct termios = 60  
	=> ... alignt after c_cc
	lua unpack:
	I4I4I4I4c6I1I1c36 
	=> iflag, oflag, cflag, lflag, dum1, ccVTIME, ccVMIN, dum2
--
can change mode if isatty()    -- impl?
just perform a tcgetattr on fd. if success, this a a tty.
	/* Return 1 if FD is a terminal, 0 if not.  */
	int __isatty (int fd)	{
		struct termios term;
		return __tcgetattr (fd, &term) == 0; 
	}
--
[/f/p3/git/tmp/musl-1.1.18-src/src/termios]$ cat tcgetattr.c 
#include <termios.h>
#include <sys/ioctl.h>

int tcgetattr(int fd, struct termios *tio)
{
        if (ioctl(fd, TCGETS, tio))
                return -1;
        return 0;
}

[/f/p3/git/tmp/musl-1.1.18-src/src/termios]$ cat tcsetattr.c 
#include <termios.h>
#include <sys/ioctl.h>
#include <errno.h>

int tcsetattr(int fd, int act, const struct termios *tio)
{
        if (act < 0 || act > 2) {
                errno = EINVAL;
                return -1;
        }
        return ioctl(fd, TCSETS+act, tio);
}

tcsetattr
TCSAFLUSH=2, TCSETS=0x5402
tcsetattr(0,TCSAFLUSH,&tio) => ioctl(0, 0x5404, &tio);




--	
#endif

