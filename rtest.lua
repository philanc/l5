



he = require "he" -- at https://github.com/philanc/he

l5 = require "l5"


local spack, sunpack = string.pack, string.unpack
local pf = he.printf

------------------------------------------------------------------------

function test_dm0()
	BLKGETSIZE64 = 0x80081272
	dn = "/dev/sda1"
	fd, err = l5.open(dn, 0, 0) --O_RDONLY, mode=0
	if not fd then print("open error", err); return end
	print(dn, fd)
	s, err = l5.ioctl(fd, BLKGETSIZE64, "", 8)
	if not s then print("ioctl error", err); return end
	size = sunpack("T", s)
	print("size, nb 512-byte sectors:", dn, size, size // 512)
	print("test_dm0: ok.")
end

function test_dm1() -- get version
	DM_VERSION= 0xc138fd00
	DM_LIST_DEVICES= 0xc138fd02
	dn = "/dev/mapper/control"
	fd, err = l5.open(dn, 0, 0) --O_RDONLY, mode=0
	if not fd then print("open error", dn, err); return end
	print(dn, fd)
	argin = spack("I4I4I4I4I4", 4, 0, 0, 312, 312) .. ("\0"):rep(800)
	s, err = l5.ioctl(fd, DM_VERSION, argin, 312)
--~ 	s, err = l5.ioctl(fd, DM_LIST_DEVICES, argin, 512)
	l5.close(fd)
	if not s then 
		print("ioctl error", err); 
		return 
	end
	print(#s)
	print(he.stohex(s, 16, " "))
	print("test_dm1: ok.")
end

function test_dm2() -- list all devices
	DM_VERSION= 0xc138fd00
	DM_LIST_DEVICES= 0xc138fd02
	dn = "/dev/mapper/control"
	fd, err = l5.open(dn, 0, 0) --O_RDONLY, mode=0
	if not fd then print("open error", dn, err); return end
	print(dn, fd)
	argin = spack("I4I4I4I4I4", 4, 0, 0, 768, 312) .. ("\0"):rep(800)
	s, err = l5.ioctl(fd, DM_LIST_DEVICES, argin, 512)
	l5.close(fd)
	if not s then 
		print("ioctl error", err); 
		return 
	end
	vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags =
		sunpack("I4I4I4I4I4I4I4I4", s)
	print(#s)
	print("vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags")
	print(vmaj, vmin, vpa, totsize, datastart, tcount, ocount, flags)
--~ 	print(he.stohex(s, 16, " "))
	da = s:sub(313)
	i = 1
	while true do
		dev, nxt, name = sunpack("I8I4z", da, i)
		pf("dev: %x  name: %s  next: %d", dev, name, nxt)
		if nxt == 0 then break end
		i = i + nxt
	end
	--~ 	print(he.stohex(da, 16, " "))
	print("test_dm2: ok.")
end


------------------------------------------------------------------------

--~ test_dm0()
--~ test_dm1()
test_dm2()


------------------------------------------------------------------------
--[[  

TEMP NOTES  


]]


	

