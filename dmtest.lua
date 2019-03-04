-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

-- dmtest.lua


-- conventions
--	em:  error message (a string)
--	eno: errno value (an integer)

------------------------------------------------------------------------
-- local definitions and utilities

local l5 = require "l5"


local spack, sunpack, strf = string.pack, string.unpack, string.format

local function pf(...) print(strf(...)) end

local function px(s) -- hex dump the string s
	for i = 1, #s-1 do
		io.write(strf("%02x", s:byte(i)))
		if i%4==0 then io.write(' ') end
		if i%8==0 then io.write(' ') end
		if i%16==0 then io.write('') end
		if i%32==0 then io.write('\n') end
	end
	io.write(strf("%02x\n", s:byte(i)))
end

local function repr(x) return string.format('%q', x) end

local function rpad(s, w, ch) 
	-- pad s to the right to width w with char ch
	return (#s < w) and s .. ch:rep(w - #s) or s
end

local function errm(eno, txt)
	-- errm(17, "open") => "open error: 17"
	-- errm(17)         => "error: 17"
	local s = "error: " .. tostring(eno)
	return txt and (txt .. " " .. s) or s
end
	
local function fget(fname)
	-- return content of file 'fname' or nil, msg in case of error
	local f, msg, s
	f, msg = io.open(fname, 'rb')
	if not f then return nil, msg end
	s, msg = f:read("*a")
	f:close()
	if not s then return nil, msg end
	return s
end

------------------------------------------------------------------------


local argsize = 512  	-- buffer size for ioctl() 
			-- should be enough for dmcrypt

local DMISIZE = 312  	-- sizeof(struct dm_ioctl)



function blkgetsize(devname)
	-- return the byte size of a block device
	fd, eno = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, errm(eno, "open") end
	local BLKGETSIZE64 = 0x80081272
	local s, eno = l5.ioctl(fd, BLKGETSIZE64, "", 8)
	l5.close(fd)
	if not s then return nil, errm(eno, "ioctl") end
	local size = ("T"):unpack(s)
	return size
end

local function fill_dmioctl(dname)
	local tot
	local flags = (1<<4)
	local dev = 0
	local s = spack("I4I4I4I4I4I4I4I4I4I4I8z",
		4, 0, 0,	-- version (must pass it, or ioctl fails)
		argsize,	-- data_size (total arg size)
		DMISIZE,	-- data_start
		1, 0,		-- target_count, open_count
		flags, 		-- flags (1<<4 for dm_table_status)
		0, 0,		-- event_nr, padding
		dev,		-- dev(u64)
		dname		-- device name
		)
	s = rpad(s, DMISIZE, '\0')
	return s
end

local function fill_dmtarget(secstart, secnb, targettype, options)
	-- struct dm_target_spec
	local DMTSIZE = 40  -- not including option string
	local len = DMTSIZE + #options + 1
	len = ((len >> 3) + 1) << 3  -- ensure multiple of 8 (alignment)
	local s = spack("I8I8I4I4c16z",
		secstart, secnb, -- sector_start, length
		0, len, 	-- status, next
		targettype, 	-- char target_type[16]
		options		-- null-terminated parameter string
		)
	s = rpad(s, len, '\0')
	return s
end

local function dm_opencontrol()
	local fd, eno = l5.open("/dev/mapper/control", 0, 0) 
		--O_RDONLY, mode=0
	return assert(fd, errm(eno, "open /dev/mapper/control"))
end

local function dm_getversion(cfd)
	local DM_VERSION= 0xc138fd00
	local arg = fill_dmioctl("")
	local s, eno = l5.ioctl(cfd, DM_VERSION, arg, argsize)
	assert(s, errm(eno, "dm_version ioctl"))
--~ 	px(s)
	local major, minor, patch = ("I4I4I4"):unpack(s)
	return major, minor, patch
end

local function dm_getdevlist(cfd)
	local DM_LIST_DEVICES= 0xc138fd02
	local arg = fill_dmioctl("")
	local s, eno = l5.ioctl(cfd, DM_LIST_DEVICES, arg, argsize)
	if not s then return nil, errm(eno, "ioctl")  end
	-- devlist is after the dm_ioctl struct
	local data = s:sub(DMISIZE + 1)
	local i, devlist = 1, {}
	local dev, nxt, name
	while true do
		dev, nxt, name = sunpack("I8I4z", data, i)
		table.insert(devlist, {dev=dev, name=name})
		if nxt == 0 then break end
		i = i + nxt
	end
	return devlist
end

local function dm_create(cfd, name)
	local DM_DEV_CREATE = 0xc138fd03
	local arg = fill_dmioctl(name)
	local s, eno = l5.ioctl(cfd, DM_DEV_CREATE, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_create") end
	local dev = sunpack("I8", s, 41)
	return dev
end

local function dm_tableload(cfd, name, secstart, secsize, ttype, options)
	local DM_TABLE_LOAD = 0xc138fd09
	local arg = fill_dmioctl(name)
	arg = arg .. fill_dmtarget(secstart, secsize, ttype, options)
	local s, eno = l5.ioctl(cfd, DM_TABLE_LOAD, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_table_load") end
	return true
end	

local function dm_suspend(cfd, name)
	DM_DEV_SUSPEND = 0xc138fd06
	local arg = fill_dmioctl(name)
	local s, eno = l5.ioctl(cfd, DM_DEV_SUSPEND, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_suspend") end
	local flags = sunpack("I4", s, 29)
	return flags
end

local function dm_remove(cfd, name)
	DM_DEV_REMOVE = 0xc138fd04
	local arg = fill_dmioctl(name)
	local s, eno = l5.ioctl(cfd, DM_DEV_REMOVE, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_dev_remove") end
	local flags = sunpack("I4", s, 29)
	return flags
end

local function dm_gettable(cfd, name)
	-- get _one_ table. (ok for basic dmcrypt)
	local DM_TABLE_STATUS = 0xc138fd0c
	local arg = fill_dmioctl(name)
	local s, eno = l5.ioctl(cfd, DM_TABLE_STATUS, arg, argsize)
	if not s then return nil, errm(eno, "ioctl dm_table_status") end
	-- for a single target,
	-- s :: struct dm_ioctl .. struct dm_target_spec .. options
	-- (tbl is here because flags was 1<<4)
	local totsiz, dstart, tcnt, ocnt, flags = sunpack("I4I4I4I4I4", s, 13)
--~ 	print("totsiz, dstart, tcnt, ocnt, flags")
--~ 	print(totsiz, dstart, tcnt, ocnt, flags)
	local data = s:sub(dstart+1, totsiz) -- struct dm_target_spec
	local tbl = {}
	local tnext, ttype
	tbl.secstart, tbl.secnb, tnext, ttype, tbl.options = 
		sunpack("I8I8xxxxI4c16z", data)
	tbl.ttype = sunpack("z", ttype)
	return tbl
end

local function dm_gettable_str(cfd, name)
	local tbl, em = dm_gettable(cfd, name)
	if not tbl then return nil, em end
	return strf("%d %d %s %s", 
		tbl.secstart, tbl.secnb, tbl.ttype, tbl.options)
end


local dm = {}

function dm.setup(dname, tblstr)
	local pat = "^(%d+) (%d+) (%S+) (.+)$"
	local start, siz, typ, opt = tblstr:match(pat)
	local cfd = dm_opencontrol()
	local r, em = dm_create(cfd, dname)
	if not r then goto close end
	r, em = dm_tableload(cfd, dname, start, siz, typ, opt)
	if not r then goto close end
	r, em = dm_suspend(cfd, dname)
	::close::
	l5.close(cfd)
	if em then return nil, em else return true end
end

function dm.remove(dname)
	local cfd = dm_opencontrol()
	return dm_remove(cfd, dname)
end

function dm.gettable(dname)
	local cfd = dm_opencontrol()
	return dm_gettable_str(cfd, dname)
end



------------------------------------------------------------------------
-- loop functions

-- see linux/loop.h

loop = {}

loop.INFO64_SIZE = 232
loop.NAME_SIZE = 64

function loop.status(devname)
	local LOOP_GET_STATUS64	= 0x4C05
	local fd, eno, s, fname
	fd, eno = l5.open(devname, 0, 0)
	if not fd then return nil, errm(eno, "open") end
	s, eno = l5.ioctl(fd, LOOP_GET_STATUS64, "", loop.INFO64_SIZE)
	l5.close(fd)
	if not s then return nil, errm(eno, "loop status") end
--~ 	px(s)
--~ 	dev, ino, _, _, _, loopno = sunpack("I8I8I8I8I8I4", s)
--~ 	pf("dev: %x  ino: %d  loopno: %d", dev, ino, loopno)
	_, fname = sunpack("c56z", s)
	return fname
end

function loop.remove(devname)
	local LOOP_CLR_FD = 0x4C01
	local fd, eno, s
	fd, eno = l5.open(devname, 0, 0)
	if not fd then return nil, errm(eno, "open") end
	s, eno = l5.ioctl(fd, LOOP_CLR_FD, "", loop.INFO64_SIZE)
	l5.close(fd)
	if not s then return nil, errm(eno, "loop remove") end
	return true
end

function loop.setup(devname, filename, ro_flag)
	-- default flags is O_RDWR(2)
	local flags = ro_flag and 0 or 2  -- 0=O_RDONLY, 2=O_RDWR
	local LOOP_SET_FD = 0x4C00
	local LOOP_SET_STATUS64	= 0x4C04
	local dfd, ffd, eno, em, arg, s
	ffd, eno = l5.open(filename, flags, 0)
	if not ffd then return nil, errm(eno, "loop setup file open") end
	dfd, eno = l5.open(devname, 0, 0)
	if not dfd then 
		l5.close(ffd)
		return nil, errm("loop setup dev open") 
	end
--~ 	print('ffd',ffd, 'dfd', dfd)
	-- LOOP_SET_FD ioctl: ffd is passed _directly_, not via a pointer
	s, eno = l5.ioctl_int(dfd, LOOP_SET_FD, ffd) 
	if not s then 
		em = errm(eno, "loop_set_fd")
		goto ret 
	end
	arg = rpad(('\0'):rep(56) .. filename, loop.INFO64_SIZE, '\0')
	s, eno = l5.ioctl(dfd, LOOP_SET_STATUS64, arg, loop.INFO64_SIZE)
	if not s then 
		em = errm(eno, "loop_set_status64")
		goto ret 
	end
	
	::ret::
	l5.close(dfd)
	l5.close(ffd)
	if err then return nil, em end
	return true
end
	


------------------------------------------------------------------------
-- tests

-- assume loop6 is available and setup on a dummy file
--	dd if=/dev/zero of=some_file bs=1M count=20
--	losetup /dev/loop6 some_file

secsize6 = 40960 -- devloop6
opt6 = "aes-xts-plain64 " ..
	"000102030405060708090a0b0c0d0e0f" ..
	"101112131415161718191a1b1c1d1e1f" ..
--~ 	" 0 7:6 0"   /dev/loop6
	" 0 /dev/loop6 0"  -- work as an input to dm.setup()
ts6 = "0 40960 crypt " .. opt6
	
	

function test_blkgetsize()
	local dn = "/dev/loop6"
	local size, em = blkgetsize(dn)
	if not size then print("test_dm0", dn, em); return end
	print("size, nb 512-byte sectors:", dn, size, size // 512)
	print("test_blkgetsize: ok.")
end


function test_dm_version() -- get version
	local cfd = dm_opencontrol()
	print("dm version - major, minor, patch:", dm_getversion(cfd))
	l5.close(cfd)
	print("test_dm_version: ok.")
end
	
	
function test_dm_devlist() -- list all devices
	local cfd = dm_opencontrol()
	dl, err = dm_getdevlist(cfd)
	l5.close(cfd)
	if not dl then print("test_dm2", err); return end
	for i, x in ipairs(dl) do
		pf("dev: %x (%d:%d)  name: %s", 
			x.dev, x.dev>>8, x.dev&0xff, x.name)
	end
	print("test_dm_devlist: ok.")
end



function test_loop_setup()
	devname = "/dev/loop6"
	filename = "/f/rtmp/l5/mb20"
	r, em = loop.setup(devname, filename)
	print(devname, filename, r, em)
	print("test_loop_setup done.")
	return r, em
end

function test_loop_status()
	local devname, fname, em
	devname = "/dev/loop6"
	fname, em = loop.status(devname)
	if not fname then
		print(devname, em)
		return nil, em
	end
	pf("%s setup on file %s", devname, fname)
	print("test_loop_status done.")
	return true
end

function test_loop_status7()
	local devname, fname, em
	devname = "/dev/loop7"
	fname, em = loop.status(devname)
	if not fname then
		print(devname, em)
		return nil, em
	end
	pf("%s setup on file %s", devname, fname)
	print("test_loop_status done.")
	return true
end

function test_loop_remove()
	local devname, s, em
	devname = "/dev/loop6"
	s, em = loop.remove(devname)
	if not s then 
		print(em)
		return nil, em
	else
		pf("%s loop removed.", devname)
	end
	print("test_loop_remove done.")
	return true
end

function test_dm_setup()
	local name = "loo6"
	r, em = dm.setup("loo6", ts6)
	if not r then
		print("test_dm_setup", em)
		return nil, em
	end
	print("test_dm_setup done.")
	return true
end

function test_dm_gettable()
	local name = "loo6"
	r, em = dm.gettable("loo6")
	if not r then
		print("test_dm_gettable", em)
		return nil, em
	else
		print("loo6 table:", r)
	end
	print("test_dm_gettable done.")
	return true
end

function test_dm_remove()
	local name = "loo6"
	r, em = dm.remove("loo6")
	if not r then
		print("test_dm_remove", em)
		return nil, em
	end
	print("test_dm_remove done.")
	return true
end



function test_mount()
	-- mount the filesystem, read a file, and umount it.
	--
--~ 	os.execute("ls -l /dev/mapper")
	local mpt = "/tmp/m6"
	local r, eno = l5.mount("/dev/mapper/loo6", mpt, "ext4", 0, "")
	if not r then
		print(errm(eno, "mount"))
		return nil, eno
	end
--~ 	os.execute("ls -l " .. mpt)
--~ 	print("cwd:", l5.getcwd())
	s = fget(mpt .. "/hello")
	print("content:", s)
--~ 	assert(s == "hello!!!\n")
	r, eno = l5.umount(mpt)
	if not r then
		print(errm(eno, "umount"))
		return nil, eno
	end
	return true
end
	
	
------------------------------------------------------------------------

test_dm_version()
--
assert(test_loop_setup())
test_blkgetsize()
--
assert(test_dm_setup())
test_dm_devlist()
test_dm_gettable()

-- First time the loop and dm setup are performed,
-- the encrypted disk must be formatted and some content 
-- written to it for test_mount():
--	mkfs.ext4 /dev/mapper/loo6
--	mkdir -p /tmp/m6
--	mount /dev/mapper/loo6 /tmp/m6
--	echo "hello!!!" > /tmp/m6/hello
--	sync; umount /tmp/m6

-- need some delay here. else mount fails (ENOENT)
-- why?  some udev issue?
l5.msleep(100) 
test_mount()

test_dm_remove()

test_loop_status() -- loop6 is still setup
test_loop_remove()
--need some delay here. 
-- else, status() shows the former assoc file for loop6... 
-- why?  some udev issue?

l5.msleep(200) 
test_loop_status() -- loop6 is gone
--~ test_loop_status7() 
--~ os.execute("echo 'losetup -a' ; losetup -a")

------------------------------------------------------------------------
--[[  

TEMP NOTES  

--

in dm table, device can be passed as "major:minor" or "/dev/devname"
eg. 7:6 or /dev/loop6.  The table returned by dm.status always use "7:6".

--

test returned flags for 0x2000 == 1<<13 -- cf dm-ioctl.h ::
DM_UEVENT_GENERATED_FLAG "If set, a uevent was generated for 
which the caller may need to wait." 
-does it work without udev?

--

]]


	
