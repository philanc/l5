



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"


function makerawmode(mode, opostflag)
	-- mode is the content of struct termios for the current tty
	-- return a termios content for tty raw mode (ie. no echo, 
	-- read one key at a time, etc.)
	-- taken from linenoise
	-- see also musl src/termios/cfmakeraw.c
	local fmt = "I4I4I4I4c6I1I1c36" -- struct termios is 60 bytes
	local iflag, oflag, cflag, lflag, dum1, ccVTIME, ccVMIN, dum2 =
		string.unpack(fmt, mode)
	-- no break, no CRtoNL, no parity check, no strip, no flow control
	-- .c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
	iflag = iflag & 0xfffffacd
	-- disable output post-processing
	if not opostflag then oflag = oflag & 0xfffffffe end
	-- set 8 bit chars -- .c_cflag |= CS8
	cflag = cflag | 0x00000030
	-- echo off, canonical off, no extended funcs, no signal (^Z ^C)
	-- .c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG)
	lflag = lflag & 0xffff7ff4
	-- return every single byte, without timeout
	ccVTIME = 0
	ccVMIN = 1
	return fmt:pack(iflag, oflag, cflag, lflag, 
			dum1, ccVTIME, ccVMIN, dum2)
end

function getmode()
	-- return mode, or nil, errno
	return l5.ioctl(0, 0x5401, "", 60)
end

function setmode(mode)
	-- return true or nil, errno
	return l5.ioctl(0, 0x5404, mode)
end

function test_mode()
	-- get current mode
	mode, err = getmode()
	print("mmmm???", err)
	print(he.stohex(mode, 16, ':'))

	print("test raw mode:  hit key, 'q' to quit.")
	-- set raw mode
	setmode(makerawmode(mode))

	while true do 
		c = io.read(1)
		if c == 'q' then break end
		print(string.byte(c))
	end
	-- reset former mode
	setmode(mode)
	print('\rback to normal cooked mode.')
end

function test_mb()
	-- test memory block (mb) methods
	mb = l5.mbnew(1024)
	assert(mb:seti(12, 123))
	assert(mb:geti(12) == 123)
--~ 	print(mb:mbgeti(100))-- may or may not be 0
	assert(mb:zero())
	assert(mb:geti(12) == 0)
	mb:zero()
	assert(mb:set(17, "abc"))
	assert(mb:get(17, 5) == "abc\0\0")
	assert(mb:geti(3) & 0xff == 97) -- !! little endian only :-)
	print("mb functions: ok.")
end

--~ test_mode()
test_mb()


--[[

--- TEMP NOTES

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

---








]]


	

