



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"

util = require "l5.util"
tty = require "l5.tty"

local spack, sunpack = string.pack, string.unpack

local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

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
	local el = l5.environ()
 	--print("environ lines:", #el)
	local r = false
	for i, line in ipairs(el) do
		r = r or line:match("PATH=.*/usr/bin")
	end
	assert(r)
	print("test_procinfo: ok.")
end

------------------------------------------------------------------------
-- test (l)stat

-- file types:  use mode & S_IFMT
S_IFMT = 0x0000f000
S_IFSOCK = 0x0000c000
S_IFLNK = 0x0000a000
S_IFREG = 0x00008000
S_IFBLK = 0x00006000
S_IFDIR = 0x00004000
S_IFCHR = 0x00002000
S_IFIFO = 0x00001000


function test_stat()
	-- assume the current dir is "some/path/l5" and contains l5.c
	os.execute("rm -f l5symlink; ln -s l5.c l5symlink")
	local lmode, lsize, lmtim, luid, lgid = l5.lstat5("l5symlink")
--~ 	he.printf("  mode: %o  size: %d  mtim: %s  uid: %d gid: %d", 
--~ 		lmode, lsize, he.isodate19(lmtim), luid, lgid)
	assert(lsize == 4)
	assert(lmode & 0xf000 == 0xa000) -- type is symlink
	assert(lmode & 0xfff == 0x01ff) -- perm is '0777'
	local target = l5.readlink("l5symlink")
	assert(target == "l5.c")
	local mode, size, mtim, uid, gid = l5.lstat5("l5.c")
--~ 	he.printf("  mode: %o  size: %d  mtim: %s  uid: %d gid: %d", 
--~ 		mode, size, he.isodate19(mtim), uid, gid)
	assert(mode & 0xf000 == 0x8000)
	assert(uid == luid and gid == lgid)
	t = l5.lstat("l5.c", {})
	assert(t[3]==mode and t[5]==uid and t[6]==gid and t[8]==size
		and t[12]==mtim)
	-- test mkdir
	local r, eno, em
	local dn = "/tmp/l5td"
	r, eno = l5.mkdir(dn)
	mode, size, mtim, uid, gid = l5.lstat5(dn)
	assert(mode & S_IFMT == S_IFDIR)
	r, eno = l5.rmdir(dn)
	assert(r)
	mode, size, mtim, uid, gid = l5.lstat5(dn)
--~ 	print('dir', mode, size)
	assert((not mode) and size==2) -- here size == errno == ENOENT
	print("test_stat: ok.")
end

------------------------------------------------------------------------
-- test ioctl() - set tty in raw mode and back to original mode


function test_tty_mode()
	-- get current mode
	local cookedmode, eno = tty.getmode()
	assert(cookedmode, errm(eno, "tty.getmode"))
	assert(cookedmode:sub(1,36) == tty.initialmode:sub(1,36))
		--why the difference, starting at c_cc[19] (tos+36) ???

	print("test raw mode (blocking):  hit key, 'q' to quit.")
	-- set raw mode
	nonblocking = nil
	local rawmode = tty.makerawmode(cookedmode, nonblocking)
	tty.setmode(rawmode)
--~ 	tty.setmode(cookedmode)
--~ 	tty.setrawmode()
	while true do 
		c = io.read(1)
		if c == 'q' then break end
		print(string.byte(c))
	end
	-- reset cooked mode
--~ 	tty.setmode(cookedmode)
	tty.restoremode()
	print("\rback to normal cooked mode.")
	
	print("test raw mode (nonblocking):  hit key, 'q' to quit.")
	-- set raw mode
	nonblocking = true
	local rawmode = tty.makerawmode(cookedmode, nonblocking)
	tty.setmode(rawmode)
	while true do 
		c = io.read(1)
		if not c then
			io.write(".")
			l5.msleep(500)
		elseif c == 'q' then break
		else	print(string.byte(c))
		end
	end
	-- reset cooked mode
--~ 	tty.setmode(cookedmode)
	tty.restoremode()
	print("\rback to normal cooked mode.")

	print("test_mode: ok.")
end

------------------------------------------------------------------------
-- test fork and other proc funcs

function test_fork()
	parpid = l5.getpid()
	pid = l5.fork()
	if pid == 0 then
		print("  child: getpid(), getppid =>", 
			l5.getpid(), l5.getppid())
		assert(parpid == l5.getppid())
		print("  child: exiting with os.exit(3)...")
		os.exit(3)
	else
--~ 		print("  parent pid =>", parpid)
		print("  parent: fork =>", pid)
		print("  parent: waiting for child...")
--~ 		l5.kill(pid, 15)
		pid, status = l5.waitpid()
		print("  parent: wait =>", pid, status)
		-- exitstatus: (status & 0xff00) >> 8
		-- termsig: status & 0x7f
		-- coredump: status & 0x80
		exit = (status & 0xff00) >> 8
		sig = status & 0x7f
		core = status & 0x80
--~ 		print("  status => exit, sig, coredump =>", exit, sig, core)
		assert(exit==3 and sig==0 and core==0)
	end
	print("test_fork: ok.")
end

------------------------------------------------------------------------

test_mb()
test_procinfo()
test_stat()
--~ test_tty_mode()
test_fork()


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

