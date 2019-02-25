

// a temp, crude tool to explore constants, types and struct sizes
// on various architectures

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
	dispsize(long)
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

	printf("---\n");
}



