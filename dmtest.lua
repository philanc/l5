-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

-- dmtest.lua

-------------------------------------------------------------------------- local definitions

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

function rpad(s, w, ch) 
	-- pad s to the right to width w with char ch
	return (#s < w) and s .. ch:rep(w - #s) or s
end

local function assert2(r, m1, m2)
	if not r then error(tostring(m1) .. ": " .. tostring(m2)) end
	return r
end

------------------------------------------------------------------------


local argsize = 512  	-- buffer size for ioctl() 
			-- should be enough for dmcrypt

local DMISIZE = 312  	-- sizeof(struct dm_ioctl)



function blkgetsize(devname)
	-- return the byte size of a block device
	fd, err = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, "open error: " .. err end
	local BLKGETSIZE64 = 0x80081272
	local s, err = l5.ioctl(fd, BLKGETSIZE64, "", 8)
	if not s then return nil, "ioctl error: " .. err end
	local size = ("T"):unpack(s)
	return size
end

function fill_dmioctl(dname)
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

function fill_dmtarget(secstart, secnb, targettype, options)
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

function dm_opencontrol()
	local fd, err = l5.open("/dev/mapper/control", 0, 0) 
		--O_RDONLY, mode=0
	return assert2(fd, "open /dev/mapper/control error", err)
end

function dm_getversion(cfd)
	local DM_VERSION= 0xc138fd00
	local arg = fill_dmioctl("")
	local s, err = l5.ioctl(cfd, DM_VERSION, arg, argsize)
	assert2(s, "ioctl error", err)
--~ 	px(s)
	local major, minor, patch = ("I4I4I4"):unpack(s)
	return major, minor, patch
end

function dm_getdevlist(cfd)
	local DM_LIST_DEVICES= 0xc138fd02
	local arg = fill_dmioctl("")
	local s, err = l5.ioctl(cfd, DM_LIST_DEVICES, arg, argsize)
	if not s then return nil, "ioctl error: " .. err end
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

function dm_create(cfd, name)
	local DM_DEV_CREATE = 0xc138fd03
	local arg = fill_dmioctl(name)
	local s, err = l5.ioctl(cfd, DM_DEV_CREATE, arg, argsize)
	if not s then return nil, "ioctl dm create error: " .. err end
	local dev = sunpack("I8", s, 41)
	return dev
end

function dm_tableload(cfd, name, secstart, secsize, ttype, options)
	local DM_TABLE_LOAD = 0xc138fd09
	local arg = fill_dmioctl(name)
	arg = arg .. fill_dmtarget(secstart, secsize, ttype, options)
	local s, err = l5.ioctl(cfd, DM_TABLE_LOAD, arg, argsize)
	if not s then print("dm_table_load error: " .. err); return end
	return true
end	

function dm_suspend(cfd, name)
	DM_DEV_SUSPEND = 0xc138fd06
	local arg = fill_dmioctl(name)
	local s, err = l5.ioctl(cfd, DM_DEV_SUSPEND, arg, argsize)
	if not s then return nil, "ioctl dm suspend error: " .. err end
	local flags = sunpack("I4", s, 29)
	return flags
end

function dm_remove(cfd, name)
	DM_DEV_REMOVE = 0xc138fd04
	local arg = fill_dmioctl(name)
	local s, err = l5.ioctl(cfd, DM_DEV_REMOVE, arg, argsize)
	if not s then return nil, "ioctl dm remove error: " .. err end
	local flags = sunpack("I4", s, 29)
	return flags
end

function dm_gettable(cfd, name)
	-- get _one_ table. (ok for basic dmcrypt)
	local DM_TABLE_STATUS = 0xc138fd0c
	local arg = fill_dmioctl(name)
	local s, err = l5.ioctl(cfd, DM_TABLE_STATUS, arg, argsize)
	if not s then return nil, "ioctl dm table_status error: " .. err end
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

function dm_gettable_str(cfd, name)
	local tbl, err = dm_gettable(cfd, name)
	if not tbl then return nil, err end
	return strf("%d %d %s %s", 
		tbl.secstart, tbl.secnb, tbl.ttype, tbl.options)
end

------------------------------------------------------------------------
-- tests




function test_dm0()
	local dn = "/dev/loop6"
	local size, errm = blkgetsize(dn)
	if not size then print("test_dm0", dn, errm); return end
	print("size, nb 512-byte sectors:", dn, size, size // 512)
	print("test_dm0: ok.")
end


function test_dm1() -- get version
	local cfd = dm_opencontrol()
	print("major, minor, patch", dm_getversion(cfd))
	l5.close(cfd)
	print("test_dm1: ok.")
end
	
	
function test_dm2() -- list all devices
	local cfd = dm_opencontrol()
	dl, err = dm_getdevlist()
	l5.close(cfd)
	if not dl then print("test_dm2", err); return end
	for i, x in ipairs(dl) do
		pf("dev: %x (%d:%d)  name: %s", 
			x.dev, x.dev>>8, x.dev&0xff, x.name)
	end
	print("test_dm2: ok.")
end

function test_dm3(name) -- get table status
	local cfd = dm_opencontrol()
	local tbl, err = dm_gettable(cfd, name)
	l5.close(cfd)
	assert2(tbl, "dm_table_status ioctl error:", err)
	pf("secstart: %d  secnb: %d  target type: %s \noptions: %s", 
		tbl.secstart, tbl.secnb, tbl.ttype, tbl.options)
	print("test_dm3: ok.")
end

function test_dm3s(name) -- get table status as a string
	local cfd = dm_opencontrol()
	local s, err = dm_gettable_str(cfd, name)
	l5.close(cfd)
	assert2(s, "dm_table_status ioctl error:", err)
	print(repr(s))
	print("test_dm3s: ok.")
end

secsize6 = 40960 -- devloop6
opt6 = "aes-xts-plain64 " ..
	"000102030405060708090a0b0c0d0e0f" ..
	"101112131415161718191a1b1c1d1e1f" ..
--~ 	" 0 7:6 0"  -- /dev/loop6
	" 0 /dev/loop6 0"  -- /dev/loop6

function dm_setup_loop6()
	local name = "loo6"
	local totsize = 768
	local cfd = dm_opencontrol()
	--
	-- create
	local r, err = dm_create(cfd, name)
	if not r then print(err); return end
--~ 	pf("dm create dev=%04x", r)
	r, err = dm_tableload(cfd, name, 0, secsize6, "crypt", opt6)
	if not r then print(err); return end
	r, err = dm_suspend(cfd, name)
	if not r then print(err); return end	
--~ 	pf("dm suspend flags=0x%x", r)
	print("dm_setup_loop6 done.")
end
	
function dm_remove_loop6()
	local name = "loo6"
	local cfd = dm_opencontrol()
	local flags, err = dm_remove(cfd, name)
	if not flags then print(err); return end
	pf("dm remove flags=0x%x", flags)
	print("dm_remove_loop6 done.")
	-- returned flags is 0x2000 == 1<<13 -- cf dm-ioctl.h ::
	-- DM_UEVENT_GENERATED_FLAG "If set, a uevent was generated for 
	-- which the caller may need to wait." 
end


------------------------------------------------------------------------

--~ test_dm0()
--~ test_dm1()
--~ test_dm2()

dm_setup_loop6()
test_dm3("loo6")
test_dm3s("loo6")
dm_remove_loop6()


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	
