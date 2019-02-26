



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"


local spack, sunpack = string.pack, string.unpack

------------------------------------------------------------------------

function test_mb()
	-- test memory block (mb) methods
	mb = l5.mbnew(1024)
	assert(mb:seti(12, 123))
	assert(mb:geti(12) == 123)
--~ 	print(mb:mbgeti(100))-- may or may not be 0
	assert(mb:zero())
	assert(mb:geti(12) == 0)
	mb:zero()
	assert(mb:set(16, "abc"))
	assert(mb:get(16, 5) == "abc\0\0")
	assert(mb:geti(2) & 0xff == 97) -- !! little endian only :-)
	print("test_mb: ok.")
end

------------------------------------------------------------------------
-- test process info

function test_procinfo()
--~ 	print(l5.getpid())
--~ 	print(l5.getppid())
--~ 	print(l5.geteuid())
--~ 	print(l5.getegid())
--~ 	print(l5.getcwd())
	assert(math.type(l5.getpid()) == "integer")
	assert(math.type(l5.getppid()) == "integer")
	assert(math.type(l5.geteuid()) == "integer")
	assert(math.type(l5.getegid()) == "integer")
	-- assume the current dir is "some/path/l5"
	assert(l5.getcwd():match(".*/l5$")) 
	local k, v = 'xyzzyzzy', 'XYZZYZZY'
	assert(os.getenv(k) == nil)
	l5.setenv(k, v); assert(os.getenv(k) == v)
	l5.unsetenv(k); assert(os.getenv(k) == nil)
	print("test_procinfo: ok.")
end

------------------------------------------------------------------------
-- test (l)stat

function test_stat()
	-- assume the current dir is "some/path/l5" and contains l5.c
	os.execute("rm -f l5symlink; ln -s l5.c l5symlink")
	local lmode, lsize, lmtim, luid, lgid = l5.lstat5("l5symlink")
	he.printf("mode: %o  size: %d  mtim: %s  uid: %d gid: %d", 
		lmode, lsize, he.isodate19(lmtim), luid, lgid)
	assert(lsize == 4)
	assert(lmode & 0xf000 == 0xa000) -- type is symlink
	assert(lmode & 0xfff == 0x01ff) -- perm is '0777'
	local target = l5.readlink("l5symlink")
	assert(target == "l5.c")
	local mode, size, mtim, uid, gid = l5.lstat5("l5.c")
	he.printf("mode: %o  size: %d  mtim: %s  uid: %d gid: %d", 
		mode, size, he.isodate19(mtim), uid, gid)
	assert(mode & 0xf000 == 0x8000)
	assert(uid == luid and gid == lgid)
	t = l5.lstat("l5.c", {})
	assert(t[3]==mode and t[5]==uid and t[6]==gid and t[8]==size
		and t[12]==mtim)

	print("test_stat: ok.")
end

------------------------------------------------------------------------
-- test ioctl() - set tty in raw mode and back to original mode

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
	print("\rback to normal cooked mode.")
	print("test_mode: ok.")
end

------------------------------------------------------------------------

test_mb()
test_procinfo()
test_stat()
--~ test_mode()



------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

