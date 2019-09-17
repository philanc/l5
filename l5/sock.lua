-- Copyright (c) 2019  Phil Leblanc  -- see LICENSE file
------------------------------------------------------------------------
-- L5 - socket interface


local l5 = require "l5"
local util = require "l5.util"

local spack, sunpack, strf = string.pack, string.unpack, string.format
local insert, concat = table.insert, table.concat
local errm, rpad, pf, px = util.errm, util.rpad, util.pf, util.px

------------------------------------------------------------------------

--[[

Notes:





]]

sock = {} -- the sock module object

------------------------------------------------------------------------
-- sockaddr ("sa") utilities

local AF_UNIX, AF_INET, AF_INET6 = 1, 2, 10

function sock.sockaddr(addr, port)
	-- turn an address (as a string) and a port number
	-- into a sockaddr struct, returned as a string
	-- addr is either an ip v4 numeric address (eg. "1.23.34.56")
	-- or a unix socket pathname (eg. "/tmp/xyz_socket")
	-- (in the case of a Unix socket, the pathname must include a '/')
	local sa
	if addr:find("/") then --assume this is an AF_UNIX socket
		if #addr > 107 then return nil, "pathname too long" end
		return spack("=Hz", AF_UNIX, addr)
	end
	-- ipv6 addr not supported yet
	-- if addr:find(":") then --assume this is an AF_INET6 socket
	-- end

	-- here, assume this is an ipv4 address
	local ippat = "(%d+)%.(%d+)%.(%d+)%.(%d+)"
	local ip1, ip2, ip3, ip4 = addr:match(ippat)
	ip1 = tonumber(ip1); ip2 = tonumber(ip2);
	ip3 = tonumber(ip3); ip4 = tonumber(ip4);
	local function bad(b) return b < 0 or b > 255 end
	if not ip1 or bad(ip1) or bad(ip2) or bad(ip3) or bad(ip4) then
		return nil, "invalid address"
	end
	if (not math.type(port) == "integer")
		or port <=0 or port > 65535 then
		return nil, "not a valid port"
	end
	return spack("<H>HBBBBI8", AF_INET, port, ip1, ip2, ip3, ip4, 0)
end

function sock.sockaddr_family(sa)
	return sunpack("<H", sa)
end

------------------------------------------------------------------------
-- so functions and constants



sock.DONTWAIT = 0x40  -- non-blocking flag for send/recv functions
sock.BUFSIZE = 4096  -- max size of a msg for send1/recv1 functions
sock.BUFSIZE1 = 1280  -- max size of a msg for send1/recv1 functions

local SOCK_STREAM = 0x01
local SOCK_DGRAM = 0x02
local SOCK_CLOEXEC = 0x80000
local SOCK_NONBLOCK = 0x0800

local EAGAIN = 11 -- same as EWOULDBLOCK (on linux and any recent unix)
local EBUSY = 16

sock.EAGAIN = EAGAIN
sock.EOF     = 0x10000	-- outside of the range of errno numbers
sock.TIMEOUT = 0x10001	

sock.AF_UNIX = 1
sock.AF_INET = 2
sock.AF_INET6 = 10

function sock.sbind(sa, nonblocking, backlog)
	-- create a stream socket object, bind it to sockaddr sa,
	-- and start listening.
	-- default options: CLOEXEC, blocking, REUSEADDR
	-- sa is a sockaddr struct encoded as a string (see sockaddr())
	-- if nonblocking is true, the socket is non-blocking
	-- backlog is the backlog size for listen(). it defaults to 32.
	-- return the socket object, or nil, errmsg
	local so = { 
		nonblocking = nonblocking, 
		backlog = backlog or 32, 
		stream = true,
		bindto = sa,
	}
	local family = sock.sockaddr_family(sa)
	local sotype = SOCK_STREAM | SOCK_CLOEXEC
	if nonblocking then sotype = sotype | SOCK_NONBLOCK end
	local fd, eno = l5.socket(family, sotype, 0)
	if not fd then return nil, eno, "socket" end
	so.fd = fd
	local r
	local SOL_SOCKET = 1
	local SO_REUSEADDR = 2
	r, eno = l5.setsockopt(so.fd, SOL_SOCKET, SO_REUSEADDR, 1)
	if not r then return nil, eno, "setsockopt" end
	r, eno = l5.bind(so.fd, sa)
	if not r then return nil, eno, "bind" end
	r, eno = l5.listen(so.fd, so.backlog)
	if not r then return nil, eno, "listen" end
	return so
end

function sock.sconnect(sa, nonblocking)
	-- create a stream socket object, and connect it to server 
	-- address sa. sa is a sockaddr string
	-- if nonblocking is true, the socket is non-blocking
	-- default options: CLOEXEC, blocking
	-- return the socket object, or nil, eno, errmsg
	local so = { 
		nonblocking = nonblocking, 
		stream = true,
		ssa = sa
	}
	local family = sock.sockaddr_family(sa)
	local sotype = SOCK_STREAM | SOCK_CLOEXEC
	if nonblocking then sotype = sotype | SOCK_NONBLOCK end
	local fd, eno = l5.socket(family, sotype, 0)
	if not fd then return nil, eno, "socket" end
	so.fd = fd
	local r
	r, eno = l5.connect(fd, sa)
	if not r then return nil, eno, "connect" end
	return so
end

function sock.dsocket(family, nonblocking)
	-- create a datagram socket object, return the fd
	-- family is 1 (unix), 2 (ip4) or 10 (ip6)
	-- if nonblocking is true, the socket is non-blocking
	local so = { 
		nonblocking = nonblocking, 
		stream = false,
		family = family,
	}
	local sotype = SOCK_DGRAM | SOCK_CLOEXEC
	if nonblocking then sotype = sotype | SOCK_NONBLOCK end
	local fd, eno = l5.socket(family, sotype, 0)
	if not fd then return nil, eno, "socket" end
	so.fd = fd
	local SOL_SOCKET = 1
	local SO_REUSEADDR = 2
	r, eno = l5.setsockopt(so.fd, SOL_SOCKET, SO_REUSEADDR, 1)
	if not r then return nil, eno, "setsockopt" end
	return so
end

function sock.bind(so, sa)
	-- bind a socket to an address (in sockaddr string form - 
	-- see sock.sockaddr())
	local r, eno = l5.bind(so.fd, sa)
	if not r then return nil, eno end
	so.sa = sa
	return true
end

	
function sock.recv(so)
	return l5.recv(so.fd, 0)
end

function sock.recvfrom(so)
	return l5.recvfrom(so.fd, 0)
end

function sock.sendto(so, msg, dest_sa)
	assert(#msg <= sock.BUFSIZE)
	return l5.sendto(so.fd, msg, 0, dest_sa)
end

function sock.close(so) 
	return l5.close(so.fd)
end

function sock.timeout(so, ms)
	local r, eno = l5.setsocktimeout(so.fd, ms)
	if not r then return nil, eno, "setsocktimeout" end
	return so
end

function sock.accept(so, nonblocking)
	-- accept a connection on server socket object so
	-- return cso, a socket object for the accepted client.
	local flags = SOCK_CLOEXEC
	if nonblocking then flags = flags | SOCK_NONBLOCK end
	local cfd, csa = l5.accept(so.fd, flags)
	if not cfd then return nil, csa end -- here csa is the errno.
	local cso = { 
		fd = cfd,
		csa = csa,
		nonblocking = nonblocking,
		stream = true,
	}
	return cso
end

-- sock readbytes and readline functions: at the moment not very efficient
-- (concat read string with buffer at each read operation - should
-- replace the buf string with a table) -- to be optimized later! 

function sock.readline(so)
	-- buffered read. read a line
	-- return line (without eol) or nil, errno
	local eno -- errno
	so.buf = so.buf or "" -- read buffer
--~ 	so.bi = so.bi or 1 -- buffer index
	while true do
		local i, j = so.buf:find("\r?\n")
		if i then -- NL found. return the line
			local l = so.buf:sub(1, i-1)
			so.buf = so.buf:sub(j + 1)
			return l
		else -- NL not found. read more bytes into buf
			local b, eno = l5.read(so.fd)
			if not b then
				return nil, eno
			end
--~ 				print("READ", b and #b)
			if #b == 0 then return nil, sock.EOF end
			so.buf = so.buf .. b
		end--if
	end--while reading a line
end

function sock.readbytes(so, n)
	-- buffered read: read n bytes
	-- return read bytes as a string, or nil, errmsg
	so.buf = so.buf or "" -- read buffer
	local nbs -- "n bytes string" -- expected result
	local eno -- errno
	while true do
		if n <= #so.buf then -- enough bytes in buf
			nbs = so.buf:sub(1, n)
			-- keep not needed bytes in buf
			so.buf = so.buf:sub(n+1)
			return nbs
		else -- not enough, read more
			local b, eno = l5.read(so.fd)
			if not b then
				return nil, eno
			end
			if #b == 0 then
				--EOF, not enough bytes
				-- return what we have
				nbs = buf
				so.buf = ""
				return nbs
			end
			so.buf = so.buf .. b
		end
	end--while reading n bytes
end

function sock.read(so, n)
	-- buffered read: if n is provided then read n bytes
	-- else read a line
	if n then return sock.readbytes(so, n) end
	return sock.readline(so)
end

function sock.write(so, str, idx, cnt)
	-- write cnt bytes from string str at index idx fo socket object
	-- return number of bytes actually written or nil, errno
	-- idx, cnt default to 1, #str
	return l5.write(so.fd, str, idx, cnt)
end

function sock.flush(so)
	return l5.fsync(so.fd)
end

function sock.getpeername(so) 
	return l5.getpeername(so.fd) 
end

function sock.getsockname(so) 
	return l5.getsockname(so.fd) 
end


--[[     ???  MUST TCP WRITE BE BUFFERED ???

-- with tcp socket, can I pass arbitrary long string to write(2)??
-- or should I send smaller blocks one at a time?  what block size??

function sock.write(so, str)
	-- write string str to the socket object.
	-- attempt to write at most BLEN bytes at a time.
	-- the string to write is buffered. if str is not provided (nil),
	-- write() attempts to continue writing the previously given string
	-- (useful for coroutine-based concurrent socket I/O).
	local BLEN = 16384
	local i, slen = 1, #str
	if str then 
		if so.wbuf then return nil. EBUSY end
		so.wbuf = str -- write buffer
		so.wi = 1  -- write buffer index
	end 
	-- here attem
	
	local n, eno
	while i < slen do
		if i + BLEN - 1 >= slen then
			BLEN = slen - i + 1
		end
		n, eno = l5.write(so.fd, str, i, BLEN)
		if not n then return nil, eno end
		i = i + n
	end
	return slen
end
]]

------------------------------------------------------------------------
return sock


