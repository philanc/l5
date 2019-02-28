

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
#include <fcntl.h>	// open flags
#include <poll.h>	// poll
#include <linux/dm-ioctl.h>	// dm ioctl
#include <sys/mount.h>	//  BLKGETSIZE64


#define dispint(x)	printf(#x "= %d\n", x);
#define dispintx(x)	printf(#x "= 0x%08x\n", x);
#define dispsize(x)	printf("sizeof " #x "= %d\n", sizeof(x));

void main() {
	printf("---\n");
	char *p;
	dispsize((char *)p)
	dispsize(int)
	dispsize(long)
	dispsize(long long)
	dispsize(pid_t)

	// stat
	dispsize(off_t)
	dispsize(uid_t)
	dispsize(mode_t)
	dispsize(nlink_t)
	dispsize(ino_t)
	dispsize(dev_t)
	dispsize(blksize_t)
	dispsize(blkcnt_t)
	//~ dispsize(__time_t)
	dispsize(time_t)
	dispsize(struct timespec)
	dispsize(struct stat)

	// path, dirs
	dispint(PATH_MAX)
	dispsize(struct dirent)

	// termios
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
	
	// ioctl
	///f/p3/git/tmp/musl-1.1.18/include/bits/ioctl.h
	dispintx(TCGETS) // 0x5401 
	dispintx(TCSETS) // 0x5402	
	
	// poll
	dispsize(struct pollfd)
	
	//open
	dispintx(O_RDONLY)
	dispintx(O_WRONLY)
	dispintx(O_RDWR)
	dispintx(O_CREAT)
	dispintx(O_DIRECTORY)
	dispintx(O_TRUNC)
	dispintx(O_APPEND)
	dispintx(O_CLOEXEC)
	//~ dispintx(O_TMPFILE)	// defined in /asm-generic/fcntl.h
	dispintx(020000000)	// O_TMPFILE (octal) in musl: 020200000
	dispintx(020200000)	//  ie O_TMPFILE | O_DIRECTORY  ?!?
	dispintx(O_EXCL)
	//~ dispintx()
	
	// dm
	printf("---dm-ioctl\n");
	dispint(DM_VERSION_MAJOR)
	dispint(DM_VERSION_MINOR)
	dispintx(DM_VERSION)
	dispintx(DM_DEV_CREATE)
	dispintx(DM_DEV_REMOVE)
	dispintx(DM_DEV_STATUS)
	dispintx(DM_TABLE_LOAD)
	dispintx(DM_TABLE_STATUS)
	dispintx(DM_LIST_DEVICES)
	dispsize(struct dm_ioctl)
	dispsize(struct dm_target_spec)
	struct dm_ioctl dmi;
	dispsize(dmi.name)
	dispsize(dmi.uuid)
	dispsize(struct dm_target_spec)
	dispintx(BLKGETSIZE64)
	dispintx(DM_MAX_TYPE_NAME)
	dispint((char*)&(dmi.name) - (char*)&dmi)
	printf("---\n");
}



