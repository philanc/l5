



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"


local spack, sunpack = string.pack, string.unpack
local pf, repr = he.printf, he.repr

------------------------------------------------------------------------

function blkgetsize(devname)
	fd, err = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, "open error: " .. err end
	local BLKGETSIZE64 = 0x80081272
	local s, err = l5.ioctl(fd, BLKGETSIZE64, "", 8)
	if not s then return nil, "ioctl error: " .. err end
	local size = ("T"):unpack(s)
	return size
end

function test_dm0()
	local dn = "/dev/sda1"
	local size, errm = blkgetsize(dn)
	if not size then print("test_dm0", dn, errm); return end
	print("size, nb 512-byte sectors:", dn, size, size // 512)
	print("test_dm0: ok.")
end

function dm_getversion()
	local DM_VERSION= 0xc138fd00
	local devname = "/dev/mapper/control"
	local fd, err = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, "open error: " .. err end
	-- caller must pass the good major version (4) or ioctl fails.
	local argin = he.rpad(spack("I4I4I4I4", 4, 0, 0, 312), 312, '\0')
	local s, err = l5.ioctl(fd, DM_VERSION, argin, 312)
	l5.close(fd)	
	if not s then return nil, "ioctl error: " .. err end
--~ 	print(he.stohex(s, 16, " "))
	local major, minor, patch = ("I4I4I4"):unpack(s)
	return major, minor, patch
end

function test_dm1() -- get version
	local major, minor, patch = dm_getversion()
	if not major then -- minor is the errmsg
		print("test_dm1", minor)
		return 
	end
	print("major, minor, patch", major, minor, patch)
	print("test_dm1: ok.")
end

function dm_getdevlist()
	local DM_LIST_DEVICES= 0xc138fd02
	local devname = "/dev/mapper/control"
	local fd, err = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then return nil, "open error: " .. err end
	-- ioctl input arg
	-- caller must pass the good major version (4) or ioctl fails.
	-- data start=312 (== sizeof struct dm_ioctl)
	-- total size=768 (make room for dev list)
	local argin = spack("I4I4I4I4I4", 4, 0, 0, 768, 312)
	argin = he.rpad(argin, 768, '\0')
	local s, err = l5.ioctl(fd, DM_LIST_DEVICES, argin, 768)
	l5.close(fd)
	if not s then return nil, "ioctl error: " .. err end
--~ 	local vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags =
--~ 		sunpack("I4I4I4I4I4I4I4I4", s)
--~ 	print(#s)
--~ 	print("vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags")
--~ 	print(vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags)
	local data = s:sub(313)
	local i = 1
	local devlist = {}
	local dev, nxt, name
	while true do
		dev, nxt, name = sunpack("I8I4z", data, i)
		table.insert(devlist, {dev=dev, name=name})
		if nxt == 0 then break end
		i = i + nxt
	end
	return devlist
end
	
	
function test_dm2() -- list all devices
	dl, err = dm_getdevlist()
	if not dl then print("test_dm2", err); return end
	for i, x in ipairs(dl) do
		pf("dev: %x (%d, %d)  name: %s", 
			x.dev, x.dev>>8, x.dev&0xff, x.name)
	end
	print("test_dm2: ok.")
end

function test_dm3() -- get status
	local name = "lua7"
	local DM_TABLE_STATUS = 0xc138fd0c
	print(name)
	local devname = "/dev/mapper/control"
	local fd, err = l5.open(devname, 0, 0) --O_RDONLY, mode=0
	if not fd then 
		print("DM_TABLE_STATUS open error:", err)
		return nil, "open error: " .. err
	end
	
	local argin = spack("I4I4I4I4I4I4I4I4", 
		4, 0, 0, 768, --version(3), data_size
		312, 1, 0,  -- data_start, target_count, open_count, 
		16 )  -- flags (in 1<<4 to get table info)
	argin = argin .. spack("I4I4I8", 0, 0, -- event_nr, padding
		0 -- dev(u64) [??]
		) .. name
	argin = he.rpad(argin, 768, '\0')
	local s, err = l5.ioctl(fd, DM_TABLE_STATUS, argin, 768)
	l5.close(fd)
	if not s then 
		print("DM_TABLE_STATUS ioctl error:", err)
	end
	-- for a single target,
	-- s :: struct dm_ioctl .. struct dm_target_spec .. tbl
	-- (tbl is here because in flags was 1<<4)
	local totsiz, dstart, tcnt, ocnt, flags = sunpack("I4I4I4I4I4", s, 13)
	print("totsiz, dstart, tcnt, ocnt, flags")
	print(totsiz, dstart, tcnt, ocnt, flags)
	local data = s:sub(dstart+1, totsiz) -- struct dm_target_spec
	local secstart, secnb, next, ttype, tbl = 
		sunpack("I8I8xxxxI4c16z", data)
	print("secstart, secnb, next, ttype")
	print(secstart, secnb, next, ttype)
	print("tbl:", tbl)
--~ 	print(repr(data))
--~ 	print(he.stohex(data, 16, " "))
	print("test_dm3: ok.")
	
end
------------------------------------------------------------------------

--~ test_dm0()
test_dm1()
--~ test_dm2()
--~ test_dm3()

------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	
