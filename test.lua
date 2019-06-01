



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"

util = require "l5.util"
tty = require "l5.tty"
fs = require "l5.fs"

local spack, sunpack = string.pack, string.unpack
local insert, concat = table.insert, table.concat

local errm, rpad, repr = util.errm, util.rpad, util.repr
local pf, px = util.pf, util.px


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
	local lmode, lsize, lmtim = l5.lstat3("l5symlink")
--~ 	he.printf("  mode: %o  size: %d  mtim: %s ", 
--~ 		lmode, lsize, he.isodate19(lmtim) )
	assert(lsize == 4)
	assert(lmode & 0xf000 == 0xa000) -- type is symlink
	assert(lmode & 0xfff == 0x01ff) -- perm is '0777'
	local target = l5.readlink("l5symlink")
	assert(target == "l5.c")
	local mode, size, mtim = l5.lstat3("l5.c")
--~ 	he.printf("  mode: %o  size: %d  mtim: %s ", 
--~ 		mode, size, he.isodate19(mtim) )
	assert(mode & 0xf000 == 0x8000)
	t = l5.lstat("l5.c", {})
	assert(t[3]==mode and t[8]==size and t[12]==mtim)
	-- test mkdir
	local r, eno, em
	local dn = "/tmp/l5td"
	r, eno = l5.mkdir(dn)
	mode, size, mtim = l5.lstat3(dn)
	assert(mode & S_IFMT == S_IFDIR)
	r, eno = l5.rmdir(dn)
	assert(r)
	mode, size, mtim = l5.lstat3(dn)
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
-- test filesystem functions


function test_fs()
	local dl, em = fs.ls1("/")
	assert(dl, em)
	local found = false
	for i, e in ipairs(dl) do
--~ 		print(e[2], e[1]) -- ftype, fname
		found = found or (e[1] == "bin" and e[2] == "d")
	end
	assert(found, "/bin not found")
	dl, em = fs.ls3("/dev/mapper")
	found = false
	for i, e in ipairs(dl) do
--~ 		print(e[2], e[1], e[3], e[4]) -- ftype, fname, mtime, size
		found = found or 
			(e[1] == "control" and e[2] == "c" and e[4] == 0)
	end
	assert(found, "/dev/mapper/control not found")
	dl, fl = fs.lsd("/bin")
	assert(dl, fl)
	local dls, fls = concat(dl, " "), concat(fl, " ")
--~ 	print("dirs: ", ds, "\nfiles: ", fs)
	assert(fls:find"bash", "bash not found in file list")
	assert(dls:find"..", ".. not found in dir list")
--~ 	print("ls0 cur dir:", concat(fs.ls0(""), ", "))
--~ 	local ffl = fs.findfiles("/etc/udev")
--~ 	local ffl = fs.findall("/etc/udev")
--~ 	he.pp(ffl)
	local pn, fa
	pn = "l5.c"; fa = fs.stat(pn)
--~ 	print(pn, fs.ftype(fa), fs.fperms(fa), fs.fsize(fa), 
--~ 		"is executable: ", fs.fexec(fa))
	assert(fs.ftype(fa)=="r" and not fs.fexec(fa))
	pn = "/bin/bash"; fa = fs.stat(pn)
--~ 	print(pn, fs.ftype(fa), fs.fperms(fa), fs.fsize(fa),
--~ 		"is executable: ", fs.fexec(fa))
	assert(fs.ftype(fa)=="r" and fs.fexec(fa))
	pn = "l5/"; fa = fs.stat(pn)
--~ 	print(pn, fs.ftype(fa), fs.fperms(fa), fs.fsize(fa),
--~ 		"is executable: ", fs.fexec(fa))
	assert(fs.ftype(fa)=="d" and not fs.fexec(fa))
	
	print("test_fs: ok.")
end




------------------------------------------------------------------------

test_procinfo()
test_stat()
--~ test_tty_mode()
--~ test_fork()
test_fs()


-- test execve
--~ l5.execve("/usr/bin/env", {"/usr/bin/env"}, {"AAA=AAAVALUE"})
--~ l5.execve("/bin/cat", {"/bin/cat", "--help"}, {"AAA=AAAVALUE"})


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

