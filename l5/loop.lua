-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------

--[[

l5 loop device functions




]]


local l5 = require "l5"
local util = require "l5.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local errm, rpad, pf = util.errm, util.rpad, util.pf

------------------------------------------------------------------------

-- see linux/loop.h

loop = {}

loop.INFO64_SIZE = 232
loop.NAME_SIZE = 64

function loop.filename(devname)
	-- return the file path associated to a loop device or nil, errno
	local LOOP_GET_STATUS64	= 0x4C05
	local fd, eno, s, fname
	fd, eno = l5.open(devname, 0, 0)
	if not fd then return nil, eno, "open dev" end
	s, eno = l5.ioctl(fd, LOOP_GET_STATUS64, "", loop.INFO64_SIZE)
	l5.close(fd)
	if not s then return nil, eno, "get_status64" end
--~ 	px(s)
--~ 	dev, ino, _, _, _, loopno = sunpack("I8I8I8I8I8I4", s)
--~ 	pf("dev: %x  ino: %d  loopno: %d", dev, ino, loopno)
	_, fname = sunpack("c56z", s)
	fname = sunpack("z", s, 57)
	return fname
end

function loop.remove(devname)
	-- remove the loop device
	local LOOP_CLR_FD = 0x4C01
	local fd, eno, s
	fd, eno = l5.open(devname, 0, 0)
	if not fd then return nil, eno, "open dev" end
	s, eno = l5.ioctl(fd, LOOP_CLR_FD, "", loop.INFO64_SIZE)
	l5.close(fd)
	if not s then return nil, eno, "remove" end
	return true
end

function loop.setup(devname, filename, ro_flag)
	-- setup the loop device
	-- default flags is O_RDWR
	local flags = ro_flag and 0 or 2  -- 0=O_RDONLY, 2=O_RDWR
	local LOOP_SET_FD = 0x4C00
	local LOOP_SET_STATUS64	= 0x4C04
	local dfd, ffd, eno, em, arg, s
	ffd, eno = l5.open(filename, flags, 0)
	if not ffd then return nil, eno, "open file" end
	dfd, eno = l5.open(devname, flags, 0) --2=rw
	if not dfd then 
		l5.close(ffd)
		return nil, eno, "open dev" 
	end
--~ 	print('ffd',ffd, 'dfd', dfd)
	-- LOOP_SET_FD ioctl: ffd is passed _directly_, not via a pointer
	s, eno = l5.ioctl_int(dfd, LOOP_SET_FD, ffd) 
	if not s then 
		em = "loop_set_fd"
		goto ret 
	end
	arg = rpad(('\0'):rep(56) .. filename, loop.INFO64_SIZE, '\0')
	s, eno = l5.ioctl(dfd, LOOP_SET_STATUS64, arg, loop.INFO64_SIZE)
	if not s then 
		em = "loop_set_status64"
		goto ret 
	end
	
	::ret::
	l5.close(dfd)
	l5.close(ffd)
	if em then return nil, eno, em end
	return true
end


------------------------------------------------------------------------
return loop	
