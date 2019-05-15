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
	-- ipaddr: a numeric ip address as a string
	-- port: a port number as an integer
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

function sock.make_sockaddr(addr, port)
	-- return a sockaddr (ipv4, or unix if port is empty)
	local sa, em
	if not port then 
		return sock.make_unix_sockaddr(addr)
	else
		return sock.make_ipv4_sockaddr(addr, port)
	end
end

function sock.sbind(addr, port, backlog)
	-- create a stream socket, bind it, and start listening
	-- socket is ipv4, or unix if port is empty
	-- default options: CLOEXEC, blocking, REUSEADDR
	-- backlog is the backlog size for listen(). it defaults to 32.
	-- return the socket fd, or nil, errmsg
	backlog = backlog or 32
	local sockaddr, em = sock.make_sockaddr(addr, port)
	if not sockaddr then return nil, em end
	local family = port and 2 or 1
	-- sock type: SOCK_STREAM = 0x00000001, SOCK_CLOEXEC = 0x80000
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
	r, eno = l5.listen(fd, backlog)
	if not r then return nil, errm(eno, "listen") end
	return fd
end

function sock.sconnect(addr, port)
	-- create a stream socket, and connect it.
	-- socket is ipv4, or unix if port is empty
	-- default options: CLOEXEC, blocking
	-- return the socket fd, or nil, errmsg
	local sockaddr, em = sock.make_sockaddr(addr, port)
	if not sockaddr then return nil, em end
	local family = port and 2 or 1
	-- sock type: SOCK_STREAM = 0x00000001, SOCK_CLOEXEC = 0x80000
	local type = 0x80001
	local fd, eno = l5.socket(family, type, 0)
	if not fd then return nil, errm(eno, "socket") end
	local r
	r, eno = l5.connect(fd, sockaddr)
	if not r then return nil, errm(eno, "connect") end
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


-- dso convenience object (wrap a datagram socket)

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
		return l5.recv(dso.fd, flags)
	end
	--
	function dso.send(dso, str, dest, flags)
		-- #str must be < sock.BUFSIZE1
		flags = flags or 0
		return l5.send(dso.fd, str, flags, dest)
	end
	--
	function dso.close(dso) return l5.close(dso.fd) end
	--
	dso.fd, em = sock.dsocket(dso.family)
	if not dso.fd then return nil, em end
	return dso
end

-- sso convenience object (wrap a stream socket)

function sock.newsso(fd)
	-- create a sso object. fd is optional 
	-- (it is used for the accept() method)
	local eno, em, sa, r
	local sso = {}
	if fd then sso.fd = fd end
	--
	function sso.bind(sso, addr, port)
		sso.fd, em = sock.sbind(addr, port)
		if not sso.fd then return nil, em end
		return sso
	end
	--
	function sso.connect(sso, addr, port)
		sso.fd, em = sock.sconnect(addr, port)
		if not sso.fd then return nil, em end
		return sso
	end
	--
	function sso.accept(sso)
		local cfd, eno = l5.accept(sso.fd)
		if not cfd then return nil, errm(eno, "accept") end
		-- return a new client sso object
		return sock.newsso(cfd)
	end
	--
	function sso.readline(sso)
		-- buffered read. read a line
		-- return line (without eol) or nil, errmsg
		local eno -- errno
		sso.buf = sso.buf or "" -- read buffer
		sso.bi = sso.bi or 1 -- buffer index
		while true do
			local i, j = sso.buf:find("\r?\n", sso.bi)
			if i then -- NL found. return the line
				local l = sso.buf:sub(sso.bi, i-1)
				sso.bi = j + 1
				return l
			else -- NL not found. read more bytes into buf
				local b, eno = l5.read(sso.fd)
				if not b then 
					return nil, errm(eno, "read") 
				end
--~ 				print("READ", b and #b)
				if #b == 0 then return nil, "EOF" end
				sso.buf = sso.buf:sub(sso.bi) .. b
			end--if	
		end--while reading a line
	end
	--
	function sso.readbytes(sso, n)
		-- buffered read: read n bytes 
		-- return read bytes as a string, or nil, errmsg
		sso.buf = sso.buf or "" -- read buffer
		sso.bi = sso.bi or 1 -- buffer index
		local nbs -- "n bytes string" -- expected result
		local nr -- number of bytes already read
		local eno -- errno
		-- rest to read in buf:
		sso.buf = sso.buf:sub(sso.bi)
		sso.bi = 1
		nr = #sso.buf -- available bytes in bt
		-- here, we have not enough bytes in buf
		local bt = { sso.buf } -- collect more in table bt
		while true do
			if n <= nr then -- enough bytes in bt
				sso.buf = table.concat(bt)
				nbs = sso.buf:sub(1, n)
				-- keep not needed bytes in buf
				sso.buf = sso.buf:sub(n+1)
				-- reset buffer index
				sso.bi = 1
				return nbs
			else -- not enough, read more
				local b, eno = l5.read(sso.fd)
				if not b then 
					return nil, errm(eno, "read")
				end
				if #b == 0 then 
					--EOF, not enough bytes
					-- return what we have
					nbs = table.concat(bt)
					return nbs
				end
				nr = nr + #b
				table.insert(bt, b)
			end
		end--while reading n bytes
	end
	--
	function sso.read(sso, n)
		-- buffered read: if n is provided then read n bytes 
		-- else read a line
		if n then return sso.readbytes(sso, n) end
		return sso.readline(sso)
	end
	--
	function sso.write(sso, str)
		-- attempt to write blen bytes at a time
		local blen = 16384
		local i, slen = 1, #str
		local n, eno
		while true do
			if i + blen - 1 >= slen then 
				blen = slen - i + 1 
			end
			n, eno = l5.write(sso.fd, str, i, blen)
			if not n then return errm(eno, "write") end
			i = i + n
		end
		return slen
	end
	--
	function sso.close(sso) return l5.close(sso.fd) end
	--
	function sso.getpeername(sso) return l5.getpeername(sso.fd) end
	function sso.getsockname(sso) return l5.getsockname(sso.fd) end
	--
	return sso
end --sock.newsso()

------------------------------------------------------------------------
return sock
