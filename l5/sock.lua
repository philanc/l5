-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- L5 socket functions


local l5 = require "l5"
local util = require "l5.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local insert, concat = table.insert, table.concat
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------

--[[

Notes:

  



]]


------------------------------------------------------------------------
-- sock functions

sock = {}

sock.DONTWAIT = 0x40  -- non-blocking flag for send/recv functions
sock.BUFSIZE1 = 1280  -- max size of a msg for send1/recv1 functions


function sock.parse_ipv4_sockaddr(sockaddr)
	-- return ipv4 address as a string and port as a number
	-- or nil, errmsg if family is not AF_INET (2) or length is not 16
	-- 
	if #sockaddr ~= 16 then 
		return nil, "bad length"
	end
	local family, port, ip1, ip2, ip3, ip4 = 	
		sunpack("<H>HBBBB", sockaddr)
	if family ~= 2 then 
		return nil, "not an IPv4 address"
	end
	local ipaddr = table.concat({ip1, ip2, ip3, ip4}, '.')
	return ipaddr, port
end --parse_ipv4_sockaddr

function sock.make_ipv4_sockaddr(ipaddr, port)
	-- return a sockaddr string or nil, errmsg
	local ippat = "(%d+)%.(%d+)%.(%d+)%.(%d+)"
	local ip1, ip2, ip3, ip4 = ipaddr:match(ippat)
	ip1 = tonumber(ip1); ip2 = tonumber(ip2); 
	ip3 = tonumber(ip3); ip4 = tonumber(ip4); 
	local function bad(b) return b < 0 or b > 255 end 
	if not ip1 or bad(ip1) or bad(ip2) or bad(ip3) or bad(ip4) then 
		return nil, "not an IPv4 address"
	end
	if (not math.type(port) == "integer") 
		or port <=0 or port > 65535 then 
		return nil, "not a valid port"
	end
	return spack("<H>HBBBBI8", 2, port, ip1, ip2, ip3, ip4, 0)
end

function sock.make_unix_sockaddr(pathname)
	if #pathname > 107 then return nil, "out of range" end
	local soaddr = spack("=Hz", 1, pathname); --AF_UNIX=1
--~ 	soaddr = rpad(soaddr, 110, '\0')
	return soaddr
end

function sock.sbind(sockaddr)
	-- create a stream socket, bind it, and start listening
	-- default options: CLOEXEC, blocking, REUSEADDR
	-- return the socket fd, or nil, errmsg
	local family = sunpack("H", sockaddr)
	-- SOCK_STREAM = 0x00000001, SOCK_CLOEXEC = 0x80000
	local type = 0x80001
	local fd, eno = l5.socket(family, type, 0)
	if not fd then return nil, errm(eno, "socket") end
	local r
	local SOL_SOCKET = 1
	local SO_KEEPALIVE = 9
	r, eno = l5.setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, 1)
	if not r then return nil, errm(eno, "setsockopt") end
	r, eno = l5.bind(fd, sockaddr)
	if not r then return nil, errm(eno, "bind") end
	local backlog = 32
	r, eno = l5.listen(fd, backlog)
	if not r then return nil, errm(eno, "listen") end
	return fd
end

function sock.dsocket(family)
	-- create a datagram socket, return the fd
	-- family is 1 (unix), 2 (ip4) or 10 (ip6)
	-- SOCK_DGRAM = 2, SOCK_CLOEXEC = 0x80000 => type = 0x80002
	local fd, eno = l5.socket(family, 0x80002, 0)
	if not fd then return nil, errm(eno, "socket") end
	return fd
end


-- dso object (wrap a datagram socket)

function sock.newdso(family)
	-- family = 1 for unix, 2 for inet, 10 for inet6
	local eno, em, fd, sa, r
	local dso = { family = family }
	--
	function dso.bind(dso, addr, port)
		if dso.family == 1 then
			sa, em = sock.make_unix_sockaddr(addr)
		else
			sa, em = sock.make_ipv4_sockaddr(addr, port)
		end
		if not sa then return nil, em end
		dso.sa = sa
		-- bind the socket to the address
		r, eno = l5.bind(dso.fd, sa)
		if not r then return nil, errm(eno, "bind") end
		return dso
	end
	--
	function dso.recv(dso, flags)
		flags = flags or 0
		return l5.recv1(dso.fd, flags)
	end
	--
	function dso.send(dso, str, dest, flags)
		-- #str must be < sock.BUFSIZE1
		flags = flags or 0
		return l5.send1(dso.fd, str, flags, dest)
	end
	--
	function dso.close(dso) return l5.close(dso.fd) end
	--
	dso.fd, em = sock.dsocket(dso.family)
	if not dso.fd then return nil, em end
	return dso
end





------------------------------------------------------------------------
return sock
