-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

-- dmtest.lua


-- conventions
--	em:  error message (a string)
--	eno: errno value (an integer)

------------------------------------------------------------------------
-- local definitions and utilities

local l5 = require "l5"

local util = require "l5.util"
local loop = require "l5.loop"
local dm = require "l5.dm"

local spack, sunpack, strf = string.pack, string.unpack, string.format

local errm, rpad, pf = util.errm, util.rpad, util.pf
local px, repr, fget = util.px, util.repr, util.fget


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
	local size, em = dm.blkgetsize(dn)
	if not size then print("test_dm0", dn, em); return end
	print("size, nb 512-byte sectors:", dn, size, size // 512)
	print("test_blkgetsize: ok.")
end


function test_dm_version() -- get version
	print("dm version - major, minor, patch:", dm.version())
	print("test_dm_version: ok.")
end
	
	
function test_dm_devlist() -- list all devices
	local dl, em = dm.devlist()
	if not dl then print(em); return end
	for i, x in ipairs(dl) do
		pf("dev: %x (%d:%d)  devname: %s   name: %s", 
			x.dev, x.dev>>8, x.dev&0xff, 
			dm.devname(x.dev), x.name )
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
	local dmdev = r
	assert(dmdev >> 8 == 0xfb)
	local dmdevname = "/dev/dm-" .. tostring(dmdev & 0xff)
	print("test_dm_setup done.  dm devname:", dmdevname)
	return dmdevname
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



function test_mount(dmdevname)
	-- mount the filesystem, read a file, and umount it.
	--
--~ 	os.execute("ls -l /dev/mapper")
--~ 	local msrc, mpt = "/dev/mapper/loo6", "/tmp/m6"
	local msrc, mpt = dmdevname, "/tmp/m6"
	pf("test_mount: mounting %s on %s...", msrc, mpt)
	local r, eno = l5.mount(msrc, mpt, "ext4", 0, "")
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
dmdevname = assert(test_dm_setup())
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
test_mount(dmdevname)

-- remove the dmcrypt layer
test_dm_remove()

test_loop_status() -- loop6 is still setup
test_loop_remove() -- remove the loop mapping
--need some delay here. 
-- else, status() shows the former assoc file for loop6... 
-- why?  some udev issue?

l5.msleep(200) 
test_loop_status() -- loop6 is gone


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


	
